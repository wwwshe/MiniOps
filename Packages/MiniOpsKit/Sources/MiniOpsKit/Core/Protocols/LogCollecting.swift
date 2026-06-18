import Foundation

/// v0.2 — Log collection provider interface (stub).
public protocol LogCollecting: Sendable {
    func collectDockerLogs(containerName: String, lines: Int) async throws -> String
    func collectFileLogs(path: String, lines: Int) async throws -> String
}

public struct UnimplementedLogCollector: LogCollecting {
    public func collectDockerLogs(containerName: String, lines: Int) async throws -> String {
        throw LogCollectorError.notImplemented
    }

    public func collectFileLogs(path: String, lines: Int) async throws -> String {
        throw LogCollectorError.notImplemented
    }
}

public enum LogCollectorError: Error {
    case notImplemented
}
