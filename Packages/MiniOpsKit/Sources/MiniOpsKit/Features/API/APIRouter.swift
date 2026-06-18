import Foundation

@MainActor
public final class APIRouter {
    private let monitoringService: MonitoringService
    private let settings: AppSettings

    public init(monitoringService: MonitoringService, settings: AppSettings = .shared) {
        self.monitoringService = monitoringService
        self.settings = settings
    }

    func route(request: HTTPRequest) async -> HTTPResponse {
        if request.path == "/api/v1/health" {
            return .json(APIHealthResponse(status: "ok"))
        }

        guard APIAuthMiddleware.isAuthorized(request: request, expectedToken: settings.apiToken) else {
            return .unauthorized()
        }

        switch request.method {
        case "GET":
            return await handleGet(request)
        case "POST":
            return await handlePost(request)
        case "PUT":
            return await handlePut(request)
        case "PATCH":
            return await handlePatch(request)
        case "DELETE":
            return await handleDelete(request)
        default:
            return .notFound()
        }
    }

    private func handleGet(_ request: HTTPRequest) async -> HTTPResponse {
        switch request.path {
        case "/api/v1/status":
            return .json(makeStatusResponse())
        case "/api/v1/metrics":
            return .json(makeMetricsResponse())
        case "/api/v1/metrics/history":
            return .json(makeMetricsHistoryResponse())
        case "/api/v1/docker":
            return .json(makeDockerResponse())
        case "/api/v1/health-checks":
            return .json(makeHealthChecksResponse())
        case "/api/v1/health-check-targets":
            return .json(makeHealthCheckTargetsResponse())
        case "/api/v1/settings":
            return .json(makeSettingsResponse())
        case "/api/v1/log-alerts":
            return .json(makeLogAlertsResponse())
        default:
            if request.path.hasPrefix("/api/v1/docker/") && request.path.hasSuffix("/logs") {
                return await fetchDockerLogs(request: request, path: request.path)
            }
            return .notFound()
        }
    }

    private func handlePost(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path == "/api/v1/settings" {
            return await updateSettings(request: request)
        }
        if request.path == "/api/v1/health-check-targets" {
            return await addHealthCheckTarget(request: request)
        }
        if request.path.hasPrefix("/api/v1/docker/") && request.path.hasSuffix("/restart") {
            return await dockerAction(request: request, path: request.path, suffix: "/restart", action: "restart")
        }
        if request.path.hasPrefix("/api/v1/docker/") && request.path.hasSuffix("/stop") {
            return await dockerAction(request: request, path: request.path, suffix: "/stop", action: "stop")
        }
        return .notFound()
    }

    private func handlePut(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path == "/api/v1/settings" {
            return await updateSettings(request: request)
        }
        if request.path == "/api/v1/health-check-targets" {
            return await replaceHealthCheckTargets(request: request)
        }
        return .notFound()
    }

    private func handlePatch(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path == "/api/v1/settings" {
            return await updateSettings(request: request)
        }
        return .notFound()
    }

    private func handleDelete(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path.hasPrefix("/api/v1/health-check-targets/") {
            return deleteHealthCheckTarget(path: request.path)
        }
        return .notFound()
    }

    private func makeSettingsResponse(docker: APIDockerResponse? = nil) -> APISettingsResponse {
        APISettingsResponse(
            dockerPath: settings.dockerPath,
            detectedDockerPath: DockerPathDetector.detect(),
            docker: docker
        )
    }

    private func updateSettings(request: HTTPRequest) async -> HTTPResponse {
        guard !request.body.isEmpty else {
            return .badRequest("Request body is required")
        }

        let decoder = JSONDecoder()
        guard let patch = try? decoder.decode(APISettingsPatch.self, from: request.body) else {
            return .badRequest("Invalid JSON body")
        }

        guard let dockerPath = patch.dockerPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dockerPath.isEmpty else {
            return .badRequest("dockerPath is required")
        }

        settings.dockerPath = dockerPath
        await monitoringService.refreshDocker()

        return .json(makeSettingsResponse(docker: makeDockerResponse()))
    }

    private func fetchDockerLogs(request: HTTPRequest, path: String) async -> HTTPResponse {
        guard let container = containerName(from: path, suffix: "/logs") else {
            return .badRequest("Container name is required")
        }

        let tail = request.queryInt("tail", default: 200)
        let result = await monitoringService.fetchDockerLogs(container: container, tail: tail)

        return .json(
            APIDockerLogsResponse(
                container: result.container,
                logs: result.logs,
                tail: result.tail,
                errorMessage: result.errorMessage,
                collectedAt: result.collectedAt
            )
        )
    }

    private func dockerAction(request: HTTPRequest, path: String, suffix: String, action: String) async -> HTTPResponse {
        guard let container = containerName(from: path, suffix: suffix) else {
            return .badRequest("Container name is required")
        }

        let result = await monitoringService.controlDockerContainer(container, action: action)
        await monitoringService.refreshDocker()

        return .json(
            APIDockerActionResponse(
                container: result.container,
                action: result.action,
                success: result.success,
                message: result.message,
                docker: makeDockerResponse(),
                collectedAt: result.collectedAt
            )
        )
    }

    private func containerName(from path: String, suffix: String) -> String? {
        let prefix = "/api/v1/docker/"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }
        guard path.count > prefix.count + suffix.count else { return nil }

        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(path.endIndex, offsetBy: -suffix.count)
        let raw = String(path[start..<end])
        let decoded = raw.removingPercentEncoding ?? raw
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : decoded
    }

    private func makeHealthCheckTargetsResponse() -> APIHealthCheckTargetsResponse {
        APIHealthCheckTargetsResponse(
            targets: settings.healthCheckTargets.map(mapHealthCheckTarget)
        )
    }

    private func replaceHealthCheckTargets(request: HTTPRequest) async -> HTTPResponse {
        guard let body = decodeHealthCheckTargetsBody(request) else {
            return .badRequest("Invalid health check targets body")
        }

        monitoringService.replaceHealthCheckTargets(body.targets.map(mapHealthCheckTargetItem))
        return .json(makeHealthCheckTargetsResponse())
    }

    private func addHealthCheckTarget(request: HTTPRequest) async -> HTTPResponse {
        guard !request.body.isEmpty else {
            return .badRequest("Request body is required")
        }

        let decoder = JSONDecoder()
        guard let item = try? decoder.decode(APIHealthCheckTargetItem.self, from: request.body) else {
            return .badRequest("Invalid health check target body")
        }

        let target = mapHealthCheckTargetItem(item)
        monitoringService.addHealthCheckTarget(target)
        return .json(makeHealthCheckTargetsResponse())
    }

    private func deleteHealthCheckTarget(path: String) -> HTTPResponse {
        let prefix = "/api/v1/health-check-targets/"
        guard path.hasPrefix(prefix) else { return .notFound() }

        let rawID = String(path.dropFirst(prefix.count))
        let idString = rawID.removingPercentEncoding ?? rawID
        guard let id = UUID(uuidString: idString) else {
            return .badRequest("Invalid target id")
        }

        monitoringService.removeHealthCheckTarget(id: id)
        return .json(makeHealthCheckTargetsResponse())
    }

    private func decodeHealthCheckTargetsBody(_ request: HTTPRequest) -> APIHealthCheckTargetsPutBody? {
        guard !request.body.isEmpty else { return nil }
        return try? JSONDecoder().decode(APIHealthCheckTargetsPutBody.self, from: request.body)
    }

    private func mapHealthCheckTarget(_ target: HealthCheckTarget) -> APIHealthCheckTargetItem {
        APIHealthCheckTargetItem(
            id: target.id.uuidString,
            name: target.name,
            url: target.urlString,
            intervalSeconds: target.intervalSeconds,
            timeoutSeconds: target.timeoutSeconds,
            expectedStatusCode: target.expectedStatusCode
        )
    }

    private func mapHealthCheckTargetItem(_ item: APIHealthCheckTargetItem) -> HealthCheckTarget {
        HealthCheckTarget(
            id: UUID(uuidString: item.id) ?? UUID(),
            name: item.name,
            urlString: item.url,
            intervalSeconds: item.intervalSeconds,
            timeoutSeconds: item.timeoutSeconds,
            expectedStatusCode: item.expectedStatusCode
        )
    }

    private func makeLogAlertsResponse() -> APILogAlertsResponse {
        let alerts = monitoringService.snapshot.logAlerts.map { alert in
            APILogAlertItem(
                id: alert.id.uuidString,
                container: alert.container,
                level: alert.level.rawValue,
                message: alert.message,
                detectedAt: alert.detectedAt
            )
        }
        return APILogAlertsResponse(alerts: alerts)
    }

    private func makeStatusResponse() -> APIStatusResponse {
        let snapshot = monitoringService.snapshot
        let dockerSummary = snapshot.dockerSummary
        let healthSummary = snapshot.healthCheckSummary

        return APIStatusResponse(
            overall: snapshot.overall.rawValue,
            metrics: APIMetricsSummary(
                cpu: round(snapshot.metrics.cpuUsagePercent * 10) / 10,
                memory: round(snapshot.metrics.memoryUsagePercent * 10) / 10,
                disk: round(snapshot.metrics.diskUsagePercent * 10) / 10
            ),
            docker: APIDockerSummary(
                total: dockerSummary.total,
                running: dockerSummary.running,
                stopped: dockerSummary.stopped,
                available: snapshot.docker.isAvailable
            ),
            healthChecks: APIHealthCheckSummary(
                total: healthSummary.total,
                healthy: healthSummary.healthy,
                unhealthy: healthSummary.unhealthy
            ),
            updatedAt: snapshot.updatedAt
        )
    }

    private func makeMetricsResponse() -> APIMetricsResponse {
        let metrics = monitoringService.snapshot.metrics
        return APIMetricsResponse(
            cpu: round(metrics.cpuUsagePercent * 10) / 10,
            memory: round(metrics.memoryUsagePercent * 10) / 10,
            disk: round(metrics.diskUsagePercent * 10) / 10,
            collectedAt: metrics.collectedAt
        )
    }

    private func makeMetricsHistoryResponse() -> APIMetricsHistoryResponse {
        APIMetricsHistoryResponse(points: monitoringService.metricsHistory)
    }

    private func makeDockerResponse() -> APIDockerResponse {
        let docker = monitoringService.snapshot.docker
        return APIDockerResponse(
            available: docker.isAvailable,
            errorMessage: docker.errorMessage,
            containers: docker.containers.map {
                APIDockerContainerItem(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status,
                    state: $0.state,
                    isRunning: $0.isRunning
                )
            },
            collectedAt: docker.collectedAt
        )
    }

    private func makeHealthChecksResponse() -> APIHealthChecksResponse {
        let results = monitoringService.snapshot.healthChecks
        return APIHealthChecksResponse(
            checks: results.map {
                APIHealthCheckItem(
                    id: $0.id.uuidString,
                    name: $0.name,
                    url: $0.urlString,
                    isHealthy: $0.isHealthy,
                    responseTimeMs: $0.responseTimeMs,
                    statusCode: $0.statusCode,
                    lastError: $0.lastError,
                    lastCheckedAt: $0.lastCheckedAt,
                    consecutiveFailures: $0.consecutiveFailures
                )
            }
        )
    }
}

public struct APIHealthResponse: Codable {
    let status: String
}

public struct APIStatusResponse: Codable {
    let overall: String
    let metrics: APIMetricsSummary
    let docker: APIDockerSummary
    let healthChecks: APIHealthCheckSummary
    let updatedAt: Date
}

public struct APIMetricsSummary: Codable {
    let cpu: Double
    let memory: Double
    let disk: Double
}

public struct APIDockerSummary: Codable {
    let total: Int
    let running: Int
    let stopped: Int
    let available: Bool
}

public struct APIHealthCheckSummary: Codable {
    let total: Int
    let healthy: Int
    let unhealthy: Int
}

public struct APIMetricsResponse: Codable {
    let cpu: Double
    let memory: Double
    let disk: Double
    let collectedAt: Date
}

public struct APIDockerResponse: Codable, Sendable {
    public let available: Bool
    public let errorMessage: String?
    public let containers: [APIDockerContainerItem]
    public let collectedAt: Date
}

public struct APIDockerContainerItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let state: String
    public let isRunning: Bool
}

public struct APIDockerLogsResponse: Codable, Sendable {
    public let container: String
    public let logs: String
    public let tail: Int
    public let errorMessage: String?
    public let collectedAt: Date
}

public struct APIDockerActionResponse: Codable, Sendable {
    public let container: String
    public let action: String
    public let success: Bool
    public let message: String?
    public let docker: APIDockerResponse?
    public let collectedAt: Date
}

public struct APIHealthChecksResponse: Codable {
    let checks: [APIHealthCheckItem]
}

public struct APIHealthCheckItem: Codable {
    let id: String
    let name: String
    let url: String
    let isHealthy: Bool
    let responseTimeMs: Int?
    let statusCode: Int?
    let lastError: String?
    let lastCheckedAt: Date
    let consecutiveFailures: Int
}

public struct APIHealthCheckTargetItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let url: String
    public let intervalSeconds: Int
    public let timeoutSeconds: Int
    public let expectedStatusCode: Int

    public init(
        id: String,
        name: String,
        url: String,
        intervalSeconds: Int,
        timeoutSeconds: Int,
        expectedStatusCode: Int
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.expectedStatusCode = expectedStatusCode
    }
}

public struct APIHealthCheckTargetsResponse: Codable, Sendable {
    public let targets: [APIHealthCheckTargetItem]
}

public struct APIHealthCheckTargetsPutBody: Codable, Sendable {
    public let targets: [APIHealthCheckTargetItem]
}

public struct APISettingsResponse: Codable, Sendable {
    public let dockerPath: String
    public let detectedDockerPath: String?
    public let docker: APIDockerResponse?

    public init(dockerPath: String, detectedDockerPath: String?, docker: APIDockerResponse? = nil) {
        self.dockerPath = dockerPath
        self.detectedDockerPath = detectedDockerPath
        self.docker = docker
    }
}

public struct APISettingsPatch: Codable, Sendable {
    public let dockerPath: String?
}

public struct APILogAlertItem: Codable, Sendable {
    public let id: String
    public let container: String
    public let level: String
    public let message: String
    public let detectedAt: Date
}

public struct APILogAlertsResponse: Codable, Sendable {
    public let alerts: [APILogAlertItem]
}
