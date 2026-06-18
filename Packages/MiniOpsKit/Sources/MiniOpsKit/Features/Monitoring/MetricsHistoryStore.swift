import Foundation

public final class MetricsHistoryStore: @unchecked Sendable {
    private let maxPoints: Int
    private var points: [MetricsHistoryPoint] = []
    private let lock = NSLock()

    public init(maxPoints: Int = 720) {
        self.maxPoints = max(1, maxPoints)
    }

    public func append(_ metrics: SystemMetrics) {
        guard metrics.collectedAt != .distantPast else { return }

        lock.lock()
        defer { lock.unlock() }

        points.append(MetricsHistoryPoint(metrics: metrics))
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }

    public func snapshot() -> [MetricsHistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return points
    }

    public func replace(_ newPoints: [MetricsHistoryPoint]) {
        lock.lock()
        defer { lock.unlock() }
        points = Array(newPoints.suffix(maxPoints))
    }
}
