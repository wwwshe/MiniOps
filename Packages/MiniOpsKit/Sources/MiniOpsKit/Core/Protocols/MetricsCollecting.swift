import Foundation

public protocol MetricsCollecting: Sendable {
    func collect() async -> SystemMetrics
}

public protocol DockerMonitoring: Sendable {
    func fetchContainers() async -> DockerSnapshot
}

public protocol HealthChecking: Sendable {
    func check(target: HealthCheckTarget) async -> HealthCheckResult
}
