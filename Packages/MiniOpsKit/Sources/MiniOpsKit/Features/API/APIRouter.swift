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

        switch (request.method, request.path) {
        case ("GET", "/api/v1/status"):
            return .json(makeStatusResponse())
        case ("GET", "/api/v1/metrics"):
            return .json(makeMetricsResponse())
        case ("GET", "/api/v1/docker"):
            return .json(makeDockerResponse())
        case ("GET", let path) where path.hasPrefix("/api/v1/docker/") && path.hasSuffix("/logs"):
            return await fetchDockerLogs(request: request, path: path)
        case ("GET", "/api/v1/health-checks"):
            return .json(makeHealthChecksResponse())
        case ("GET", "/api/v1/settings"):
            return .json(makeSettingsResponse())
        case ("PATCH", "/api/v1/settings"):
            return await updateSettings(request: request)
        case ("POST", "/api/v1/settings"):
            return await updateSettings(request: request)
        case ("PUT", "/api/v1/settings"):
            return await updateSettings(request: request)
        default:
            return .notFound()
        }
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
        let prefix = "/api/v1/docker/"
        let suffix = "/logs"
        guard path.count > prefix.count + suffix.count else {
            return .badRequest("Container name is required")
        }

        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(path.endIndex, offsetBy: -suffix.count)
        let rawContainer = String(path[start..<end])
        let container = rawContainer.removingPercentEncoding ?? rawContainer

        guard !container.isEmpty else {
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

public struct APIDockerContainerItem: Codable {
    let id: String
    let name: String
    let status: String
    let state: String
    let isRunning: Bool
}

public struct APIDockerLogsResponse: Codable, Sendable {
    public let container: String
    public let logs: String
    public let tail: Int
    public let errorMessage: String?
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
