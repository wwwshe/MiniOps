import Foundation

/// v0.4 — Slack / notification provider interface (stub).
public protocol NotificationSending: Sendable {
    func sendAlert(title: String, body: String) async throws
}

public struct UnimplementedNotificationSender: NotificationSending {
    public func sendAlert(title: String, body: String) async throws {
        throw NotificationError.notImplemented
    }
}

public enum NotificationError: Error {
    case notImplemented
}
