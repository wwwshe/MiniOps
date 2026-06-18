import Foundation

public enum RemoteMonitoringError: LocalizedError {
    case invalidBaseURL
    case unauthorized
    case serverError(Int)
    case decodingFailed
    case tlsOnPlainHTTP
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "서버 URL이 올바르지 않습니다. 예: http://192.168.0.10:8787"
        case .unauthorized:
            return "API Token이 올바르지 않습니다."
        case .serverError(let code):
            return "서버 오류 (HTTP \(code))"
        case .decodingFailed:
            return "서버 응답을 해석할 수 없습니다."
        case .tlsOnPlainHTTP:
            return "TLS 연결 실패. MiniOps API는 암호화(HTTPS)가 아닌 http:// 로 접속하세요."
        case .network(let error):
            if let urlError = error as? URLError, Self.isTLSError(urlError) {
                return RemoteMonitoringError.tlsOnPlainHTTP.errorDescription
            }
            return error.localizedDescription
        }
    }

    static func isTLSError(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .clientCertificateRejected,
             .cannotLoadFromNetwork:
            return true
        default:
            return error.errorCode == -1200
        }
    }
}

public final class RemoteMonitoringClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func fetchSnapshot(baseURL: String, token: String) async throws -> ServerStatusSnapshot {
        let root = try normalizedBaseURL(baseURL)

        async let statusTask  = fetch(APIStatusResponse.self,       base: root, path: "/api/v1/status",       token: token)
        async let metricsTask = fetch(APIMetricsResponse.self,      base: root, path: "/api/v1/metrics",      token: token)
        async let dockerTask  = fetch(APIDockerResponse.self,       base: root, path: "/api/v1/docker",       token: token)
        async let healthTask  = fetch(APIHealthChecksResponse.self, base: root, path: "/api/v1/health-checks",token: token)
        async let logTask     = fetchOptional(APILogAlertsResponse.self, base: root, path: "/api/v1/log-alerts", token: token)

        let status  = try await statusTask
        let metrics = try await metricsTask
        let docker  = try await dockerTask
        let health  = try await healthTask
        let logAlerts = await logTask

        return mapSnapshot(status: status, metrics: metrics, docker: docker, health: health, logAlerts: logAlerts)
    }

    public func fetchMetricsHistory(baseURL: String, token: String) async throws -> APIMetricsHistoryResponse {
        let root = try normalizedBaseURL(baseURL)
        return try await fetch(APIMetricsHistoryResponse.self, base: root, path: "/api/v1/metrics/history", token: token)
    }

    /// 404 등 실패해도 nil 반환 (하위 호환)
    private func fetchOptional<T: Decodable>(_ type: T.Type, base: URL, path: String, token: String) async -> T? {
        try? await fetch(type, base: base, path: path, token: token)
    }

    private func normalizedBaseURL(_ baseURL: String) throws -> URL {
        guard let url = RemoteAPIURL.normalize(baseURL) else {
            throw RemoteMonitoringError.invalidBaseURL
        }
        return url
    }

    private func fetch<T: Decodable>(
        _ type: T.Type,
        base: URL,
        path: String,
        token: String
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: base) else {
            throw RemoteMonitoringError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let urlError = error as? URLError, RemoteMonitoringError.isTLSError(urlError) {
                throw RemoteMonitoringError.tlsOnPlainHTTP
            }
            throw RemoteMonitoringError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteMonitoringError.serverError(0)
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw RemoteMonitoringError.unauthorized
        default:
            throw RemoteMonitoringError.serverError(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RemoteMonitoringError.decodingFailed
        }
    }

    private func mapSnapshot(
        status: APIStatusResponse,
        metrics: APIMetricsResponse,
        docker: APIDockerResponse,
        health: APIHealthChecksResponse,
        logAlerts: APILogAlertsResponse?
    ) -> ServerStatusSnapshot {
        let overall = OverallStatus(rawValue: status.overall) ?? .healthy

        let systemMetrics = SystemMetrics(
            cpuUsagePercent: metrics.cpu,
            memoryUsagePercent: metrics.memory,
            diskUsagePercent: metrics.disk,
            collectedAt: metrics.collectedAt
        )

        let dockerSnapshot = DockerSnapshot(
            containers: docker.containers.map {
                DockerContainer(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status,
                    state: $0.state,
                    cpuPercent: $0.cpuPercent,
                    memPercent: $0.memPercent,
                    memUsage: $0.memUsage
                )
            },
            isAvailable: docker.available,
            errorMessage: docker.errorMessage,
            collectedAt: docker.collectedAt
        )

        let healthChecks = health.checks.map { item in
            HealthCheckResult(
                id: UUID(uuidString: item.id) ?? UUID(),
                targetID: UUID(uuidString: item.id) ?? UUID(),
                name: item.name,
                urlString: item.url,
                isHealthy: item.isHealthy,
                responseTimeMs: item.responseTimeMs,
                statusCode: item.statusCode,
                lastError: item.lastError,
                lastCheckedAt: item.lastCheckedAt,
                consecutiveFailures: item.consecutiveFailures
            )
        }

        let mappedLogAlerts = logAlerts?.alerts.compactMap { item -> LogAlert? in
            guard let level = LogAlert.LogAlertLevel(rawValue: item.level) else { return nil }
            return LogAlert(
                id: UUID(uuidString: item.id) ?? UUID(),
                container: item.container,
                level: level,
                message: item.message,
                detectedAt: item.detectedAt
            )
        } ?? []

        return ServerStatusSnapshot(
            overall: overall,
            metrics: systemMetrics,
            docker: dockerSnapshot,
            healthChecks: healthChecks,
            logAlerts: mappedLogAlerts,
            updatedAt: status.updatedAt
        )
    }
}
