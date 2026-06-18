import Foundation

public final class HealthCheckService: HealthChecking, @unchecked Sendable {
    private let session: URLSession
    private let settings: AppSettings

    public init(settings: AppSettings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func check(target: HealthCheckTarget) async -> HealthCheckResult {
        guard !settings.isSelfReferencingHealthCheck(target.urlString, apiPort: settings.apiPort) else {
            return HealthCheckResult(
                id: target.id,
                targetID: target.id,
                name: target.name,
                urlString: target.urlString,
                isHealthy: false,
                responseTimeMs: nil,
                statusCode: nil,
                lastError: "Cannot health-check MiniOps API URL",
                lastCheckedAt: Date(),
                consecutiveFailures: 0
            )
        }

        guard let url = target.url else {
            return failureResult(
                target: target,
                error: "Invalid URL",
                previousFailures: 0
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(target.timeoutSeconds)

        let start = Date()

        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                return failureResult(
                    target: target,
                    error: "Invalid response",
                    previousFailures: 0,
                    responseTimeMs: elapsed
                )
            }

            let isHealthy = httpResponse.statusCode == target.expectedStatusCode
            return HealthCheckResult(
                id: target.id,
                targetID: target.id,
                name: target.name,
                urlString: target.urlString,
                isHealthy: isHealthy,
                responseTimeMs: elapsed,
                statusCode: httpResponse.statusCode,
                lastError: isHealthy ? nil : "Expected \(target.expectedStatusCode), got \(httpResponse.statusCode)",
                lastCheckedAt: Date(),
                consecutiveFailures: 0
            )
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return failureResult(
                target: target,
                error: error.localizedDescription,
                previousFailures: 0,
                responseTimeMs: elapsed
            )
        }
    }

    public func check(
        target: HealthCheckTarget,
        previousResult: HealthCheckResult?
    ) async -> HealthCheckResult {
        var result = await check(target: target)

        let previousFailures = previousResult?.consecutiveFailures ?? 0
        if result.isHealthy {
            result.consecutiveFailures = 0
        } else {
            result.consecutiveFailures = previousFailures + 1
        }

        return result
    }

    private func failureResult(
        target: HealthCheckTarget,
        error: String,
        previousFailures: Int,
        responseTimeMs: Int? = nil
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: target.id,
            targetID: target.id,
            name: target.name,
            urlString: target.urlString,
            isHealthy: false,
            responseTimeMs: responseTimeMs,
            statusCode: nil,
            lastError: error,
            lastCheckedAt: Date(),
            consecutiveFailures: previousFailures + 1
        )
    }
}
