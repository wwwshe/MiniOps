import Foundation

public struct MetricsHistoryPoint: Codable, Sendable, Equatable, Identifiable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let cpu: Double
    public let memory: Double
    public let disk: Double

    public init(timestamp: Date, cpu: Double, memory: Double, disk: Double) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
    }

    public init(metrics: SystemMetrics) {
        self.timestamp = metrics.collectedAt
        self.cpu = metrics.cpuUsagePercent
        self.memory = metrics.memoryUsagePercent
        self.disk = metrics.diskUsagePercent
    }
}

public struct APIMetricsHistoryResponse: Codable, Sendable {
    public let points: [MetricsHistoryPoint]
}
