import Foundation

public struct HealthCheckTarget: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var urlString: String
    public var intervalSeconds: Int
    public var timeoutSeconds: Int
    public var expectedStatusCode: Int

    public init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        intervalSeconds: Int = 60,
        timeoutSeconds: Int = 10,
        expectedStatusCode: Int = 200
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.expectedStatusCode = expectedStatusCode
    }

    public var url: URL? {
        URL(string: urlString)
    }
}

public struct HealthCheckResult: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let targetID: UUID
    public let name: String
    public let urlString: String
    public var isHealthy: Bool
    public var responseTimeMs: Int?
    public var statusCode: Int?
    public var lastError: String?
    public var lastCheckedAt: Date
    public var consecutiveFailures: Int

    public static func initial(for target: HealthCheckTarget) -> HealthCheckResult {
        HealthCheckResult(
            id: target.id,
            targetID: target.id,
            name: target.name,
            urlString: target.urlString,
            isHealthy: true,
            responseTimeMs: nil,
            statusCode: nil,
            lastError: nil,
            lastCheckedAt: .distantPast,
            consecutiveFailures: 0
        )
    }
}
