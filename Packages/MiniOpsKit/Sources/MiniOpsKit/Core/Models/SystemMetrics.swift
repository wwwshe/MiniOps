import Foundation

public struct SystemMetrics: Codable, Equatable, Sendable {
    public var cpuUsagePercent: Double
    public var memoryUsagePercent: Double
    public var diskUsagePercent: Double
    public var collectedAt: Date

    public static let empty = SystemMetrics(
        cpuUsagePercent: 0,
        memoryUsagePercent: 0,
        diskUsagePercent: 0,
        collectedAt: .distantPast
    )
}
