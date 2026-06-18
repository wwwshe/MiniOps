import Foundation

public struct DockerContainer: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let state: String

    public var isRunning: Bool {
        state.lowercased() == "running"
    }

    public var displayStatus: String {
        isRunning ? "Running" : "Exited"
    }
}

public struct DockerSnapshot: Codable, Equatable, Sendable {
    public var containers: [DockerContainer]
    public var isAvailable: Bool
    public var errorMessage: String?
    public var collectedAt: Date

    public static let unavailable = DockerSnapshot(
        containers: [],
        isAvailable: false,
        errorMessage: "Docker unavailable",
        collectedAt: .distantPast
    )
}
