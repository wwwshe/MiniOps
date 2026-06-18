import Foundation

public struct LogAlert: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let container: String
    public let level: LogAlertLevel
    public let message: String
    public let detectedAt: Date

    public init(id: UUID = UUID(), container: String, level: LogAlertLevel, message: String, detectedAt: Date = Date()) {
        self.id = id
        self.container = container
        self.level = level
        self.message = message
        self.detectedAt = detectedAt
    }

    public enum LogAlertLevel: String, Codable, Sendable {
        case warn
        case error

        public var displayName: String {
            switch self {
            case .warn: return "경고"
            case .error: return "에러"
            }
        }
    }
}

public enum OverallStatus: String, Codable, Sendable {
    case healthy
    case warning
    case critical

    public var displayName: String {
        switch self {
        case .healthy: return "정상"
        case .warning: return "경고"
        case .critical: return "장애"
        }
    }
}

public struct ServerStatusSnapshot: Codable, Equatable, Sendable {
    public var overall: OverallStatus
    public var metrics: SystemMetrics
    public var docker: DockerSnapshot
    public var healthChecks: [HealthCheckResult]
    public var logAlerts: [LogAlert]
    public var updatedAt: Date

    public static let empty = ServerStatusSnapshot(
        overall: .healthy,
        metrics: .empty,
        docker: .unavailable,
        healthChecks: [],
        logAlerts: [],
        updatedAt: .distantPast
    )

    public var dockerSummary: (total: Int, running: Int, stopped: Int) {
        let total = docker.containers.count
        let running = docker.containers.filter(\.isRunning).count
        return (total, running, total - running)
    }

    public var healthCheckSummary: (total: Int, healthy: Int, unhealthy: Int) {
        let total = healthChecks.count
        let healthy = healthChecks.filter(\.isHealthy).count
        return (total, healthy, total - healthy)
    }
}
