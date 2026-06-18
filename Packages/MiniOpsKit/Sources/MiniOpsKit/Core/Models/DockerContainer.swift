import Foundation

public struct DockerContainer: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let state: String
    public var cpuPercent: Double?
    public var memPercent: Double?
    public var memUsage: String?

    public init(id: String, name: String, status: String, state: String,
                cpuPercent: Double? = nil, memPercent: Double? = nil, memUsage: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.state = state
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
        self.memUsage = memUsage
    }

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
