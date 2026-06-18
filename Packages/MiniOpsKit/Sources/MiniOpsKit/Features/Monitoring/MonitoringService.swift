import Foundation
import Observation

@Observable
@MainActor
public final class MonitoringService {
    public private(set) var snapshot: ServerStatusSnapshot = .empty
    public private(set) var connectionError: String?
    public private(set) var isLoadingRemote = false

    private let settings: AppSettings
    private let metricsCollector: SystemMetricsCollector
    private let dockerMonitor: DockerMonitor
    private let healthCheckService: HealthCheckService
    private let remoteClient: RemoteMonitoringClient

    private var pollingTask: Task<Void, Never>?
    private var dockerTask: Task<Void, Never>?
    private var healthCheckTasks: [UUID: Task<Void, Never>] = [:]
    private var healthCheckResults: [UUID: HealthCheckResult] = [:]

    public var displaySourceName: String {
        if settings.isClientMode {
            return settings.remoteServerName
        }
        return Host.current().localizedName ?? "This Mac"
    }

    public init(
        settings: AppSettings = .shared,
        metricsCollector: SystemMetricsCollector = SystemMetricsCollector(),
        dockerMonitor: DockerMonitor = DockerMonitor(),
        healthCheckService: HealthCheckService = HealthCheckService(),
        remoteClient preferredRemoteClient: RemoteMonitoringClient = RemoteMonitoringClient()
    ) {
        self.settings = settings
        self.metricsCollector = metricsCollector
        self.dockerMonitor = dockerMonitor
        self.healthCheckService = healthCheckService
        self.remoteClient = preferredRemoteClient
    }

    public func start() {
        stop()
        connectionError = nil

        if settings.isClientMode {
            startRemotePolling()
        } else {
            startLocalPolling()
        }
    }

    public func stop() {
        pollingTask?.cancel()
        dockerTask?.cancel()
        healthCheckTasks.values.forEach { $0.cancel() }
        healthCheckTasks.removeAll()
        pollingTask = nil
        dockerTask = nil
    }

    public func restart() {
        start()
    }

    public func restartHealthChecks() {
        guard settings.isAgentMode else { return }
        healthCheckTasks.values.forEach { $0.cancel() }
        healthCheckTasks.removeAll()

        for target in settings.healthCheckTargets {
            startHealthCheckLoop(for: target)
        }

        rebuildLocalSnapshot()
    }

    // MARK: - Remote (Client Mode)

    private func startRemotePolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchRemoteSnapshot()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func fetchRemoteSnapshot() async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty else {
            connectionError = "원격 서버 URL을 설정하세요."
            return
        }

        guard !token.isEmpty else {
            connectionError = "API Token을 설정하세요."
            return
        }

        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let remoteSnapshot = try await remoteClient.fetchSnapshot(baseURL: baseURL, token: token)
            snapshot = remoteSnapshot
            connectionError = nil
        } catch {
            connectionError = error.localizedDescription
        }
    }

    // MARK: - Local (Agent Mode)

    private func startLocalPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.collectMetrics()
                try? await Task.sleep(for: .seconds(5))
            }
        }

        dockerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.collectDocker()
                try? await Task.sleep(for: .seconds(10))
            }
        }

        restartHealthChecks()
    }

    private func startHealthCheckLoop(for target: HealthCheckTarget) {
        let interval = max(target.intervalSeconds, 5)

        healthCheckTasks[target.id] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runHealthCheck(for: target)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func collectMetrics() async {
        guard settings.isAgentMode else { return }
        let metrics = await metricsCollector.collect()
        snapshot.metrics = metrics
        snapshot.updatedAt = Date()
        rebuildLocalSnapshot()
    }

    private func collectDocker() async {
        guard settings.isAgentMode else { return }
        let docker = await dockerMonitor.fetchContainers()
        snapshot.docker = docker
        snapshot.updatedAt = Date()
        rebuildLocalSnapshot()
    }

    private func runHealthCheck(for target: HealthCheckTarget) async {
        guard settings.isAgentMode else { return }
        let previous = healthCheckResults[target.id]
        let result = await healthCheckService.check(target: target, previousResult: previous)
        healthCheckResults[target.id] = result
        snapshot.healthChecks = settings.healthCheckTargets.compactMap { healthCheckResults[$0.id] }
        snapshot.updatedAt = Date()
        rebuildLocalSnapshot()
    }

    private func rebuildLocalSnapshot() {
        snapshot.healthChecks = settings.healthCheckTargets.compactMap { target in
            healthCheckResults[target.id] ?? HealthCheckResult.initial(for: target)
        }

        snapshot.overall = computeOverallStatus()
        snapshot.updatedAt = Date()
    }

    private func computeOverallStatus() -> OverallStatus {
        let unhealthyChecks = snapshot.healthChecks.filter { !$0.isHealthy }
        let criticalChecks = unhealthyChecks.filter { $0.consecutiveFailures >= 3 }
        if !criticalChecks.isEmpty {
            return .critical
        }

        if snapshot.metrics.memoryUsagePercent >= 90 || snapshot.metrics.diskUsagePercent >= 95 {
            return .critical
        }

        if !unhealthyChecks.isEmpty {
            return .warning
        }

        if snapshot.metrics.cpuUsagePercent >= 85 || snapshot.metrics.memoryUsagePercent >= 80 {
            return .warning
        }

        let stoppedContainers = snapshot.docker.containers.filter { !$0.isRunning }
        if !stoppedContainers.isEmpty && snapshot.docker.isAvailable {
            return .warning
        }

        return .healthy
    }
}
