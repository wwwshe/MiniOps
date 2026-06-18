import Foundation

public enum RemoteMonitoringError: LocalizedError {
    case invalidBaseURL
    case unauthorized
    case serverError(Int)
    case decodingFailed
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "서버 URL이 올바르지 않습니다."
        case .unauthorized:
            return "API Token이 올바르지 않습니다."
        case .serverError(let code):
            return "서버 오류 (HTTP \(code))"
        case .decodingFailed:
            return "서버 응답을 해석할 수 없습니다."
        case .network(let error):
            return error.localizedDescription
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

        async let statusTask = fetch(APIStatusResponse.self, base: root, path: "/api/v1/status", token: token)
        async let metricsTask = fetch(APIMetricsResponse.self, base: root, path: "/api/v1/metrics", token: token)
        async let dockerTask = fetch(APIDockerResponse.self, base: root, path: "/api/v1/docker", token: token)
        async let healthTask = fetch(APIHealthChecksResponse.self, base: root, path: "/api/v1/health-checks", token: token)

        let status = try await statusTask
        let metrics = try await metricsTask
        let docker = try await dockerTask
        let health = try await healthTask

        return mapSnapshot(status: status, metrics: metrics, docker: docker, health: health)
    }

    private func normalizedBaseURL(_ baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
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
        health: APIHealthChecksResponse
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
                    state: $0.state
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

        return ServerStatusSnapshot(
            overall: overall,
            metrics: systemMetrics,
            docker: dockerSnapshot,
            healthChecks: healthChecks,
            updatedAt: status.updatedAt
        )
    }
}

// Fix typo serverided -> serverError - I made a typo, need to fix
