import Foundation

@MainActor
public final class APIRouter {
    private let monitoringService: MonitoringService
    private let settings: AppSettings

    public init(monitoringService: MonitoringService, settings: AppSettings = .shared) {
        self.monitoringService = monitoringService
        self.settings = settings
    }

    func route(request: HTTPRequest) -> HTTPResponse {
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
        case ("GET", "/api/v1/health-checks"):
            return .json(makeHealthChecksResponse())
        default:
            return .notFound()
        }
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

public struct APIDockerResponse: Codable {
    let available: Bool
    let errorMessage: String?
    let containers: [APIDockerContainerItem]
    let collectedAt: Date
}

public struct APIDockerContainerItem: Codable {
    let id: String
    let name: String
    let status: String
    let state: String
    let isRunning: Bool
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
