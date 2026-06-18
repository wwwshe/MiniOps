import Foundation

/// v0.3 — AI log analysis provider interface (stub).
public protocol AIAnalyzing: Sendable {
    func summarizeLogs(_ logs: String) async throws -> String
    func analyzeIncident(context: String) async throws -> String
}

public struct UnimplementedAIAnalyzer: AIAnalyzing {
    public func summarizeLogs(_ logs: String) async throws -> String {
        throw AIAnalyzerError.notImplemented
    }

    public func analyzeIncident(context: String) async throws -> String {
        throw AIAnalyzerError.notImplemented
    }
}

public enum AIAnalyzerError: Error {
    case notImplemented
}
