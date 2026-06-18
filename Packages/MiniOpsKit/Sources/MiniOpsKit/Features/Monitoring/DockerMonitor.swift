import Foundation

public struct DockerLogsResult: Codable, Sendable, Equatable {
    public let container: String
    public let logs: String
    public let tail: Int
    public let errorMessage: String?
    public let collectedAt: Date

    public init(container: String, logs: String, tail: Int, errorMessage: String?, collectedAt: Date) {
        self.container = container
        self.logs = logs
        self.tail = tail
        self.errorMessage = errorMessage
        self.collectedAt = collectedAt
    }
}

public struct DockerActionResult: Codable, Sendable, Equatable {
    public let container: String
    public let action: String
    public let success: Bool
    public let message: String?
    public let collectedAt: Date

    public init(container: String, action: String, success: Bool, message: String?, collectedAt: Date) {
        self.container = container
        self.action = action
        self.success = success
        self.message = message
        self.collectedAt = collectedAt
    }
}

public final class DockerMonitor: DockerMonitoring, @unchecked Sendable {
    private let settings: AppSettings

    public init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    public func fetchContainers() async -> DockerSnapshot {
        let dockerPath = settings.dockerPath

        guard FileManager.default.isExecutableFile(atPath: dockerPath) else {
            return DockerSnapshot(
                containers: [],
                isAvailable: false,
                errorMessage: "Docker CLI not found at \(dockerPath)",
                collectedAt: Date()
            )
        }

        do {
            let output = try await runProcess(executable: dockerPath, arguments: [
                "ps", "-a", "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.State}}"
            ])

            let containers = output
                .split(separator: "\n")
                .compactMap(parseLine)

            return DockerSnapshot(
                containers: containers,
                isAvailable: true,
                errorMessage: nil,
                collectedAt: Date()
            )
        } catch {
            return DockerSnapshot(
                containers: [],
                isAvailable: false,
                errorMessage: error.localizedDescription,
                collectedAt: Date()
            )
        }
    }

    public func fetchLogs(container: String, tail: Int = 200) async -> DockerLogsResult {
        let trimmed = container.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineCount = min(max(tail, 1), 2000)
        let dockerPath = settings.dockerPath

        guard !trimmed.isEmpty else {
            return DockerLogsResult(
                container: trimmed,
                logs: "",
                tail: lineCount,
                errorMessage: "Container name is required",
                collectedAt: Date()
            )
        }

        guard FileManager.default.isExecutableFile(atPath: dockerPath) else {
            return DockerLogsResult(
                container: trimmed,
                logs: "",
                tail: lineCount,
                errorMessage: "Docker CLI not found at \(dockerPath)",
                collectedAt: Date()
            )
        }

        do {
            let output = try await runProcess(executable: dockerPath, arguments: [
                "logs", "--tail", String(lineCount), trimmed
            ])
            return DockerLogsResult(
                container: trimmed,
                logs: output,
                tail: lineCount,
                errorMessage: nil,
                collectedAt: Date()
            )
        } catch {
            return DockerLogsResult(
                container: trimmed,
                logs: "",
                tail: lineCount,
                errorMessage: error.localizedDescription,
                collectedAt: Date()
            )
        }
    }

    /// 컨테이너 이름 → (cpuPercent, memPercent, memUsage) 딕셔너리 반환
    public func fetchStats() async -> [String: (cpu: Double, mem: Double, memUsage: String)] {
        let dockerPath = settings.dockerPath
        guard FileManager.default.isExecutableFile(atPath: dockerPath) else { return [:] }

        guard let output = try? await runProcess(
            executable: dockerPath,
            arguments: ["stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}"]
        ) else { return [:] }

        var result: [String: (cpu: Double, mem: Double, memUsage: String)] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { continue }

            let name     = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let cpuStr   = String(parts[1]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            let memStr   = String(parts[2]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            let memUsage = String(parts[3]).components(separatedBy: " /").first?.trimmingCharacters(in: .whitespaces) ?? ""

            guard let cpu = Double(cpuStr), let mem = Double(memStr) else { continue }
            result[name] = (cpu, mem, memUsage)
        }

        return result
    }

    public func restartContainer(_ container: String) async -> DockerActionResult {
        await runContainerAction(container, action: "restart", arguments: ["restart", container])
    }

    public func stopContainer(_ container: String) async -> DockerActionResult {
        await runContainerAction(container, action: "stop", arguments: ["stop", container])
    }

    private func runContainerAction(
        _ container: String,
        action: String,
        arguments: [String]
    ) async -> DockerActionResult {
        let trimmed = container.trimmingCharacters(in: .whitespacesAndNewlines)
        let dockerPath = settings.dockerPath

        guard !trimmed.isEmpty else {
            return DockerActionResult(
                container: trimmed,
                action: action,
                success: false,
                message: "Container name is required",
                collectedAt: Date()
            )
        }

        guard FileManager.default.isExecutableFile(atPath: dockerPath) else {
            return DockerActionResult(
                container: trimmed,
                action: action,
                success: false,
                message: "Docker CLI not found at \(dockerPath)",
                collectedAt: Date()
            )
        }

        do {
            _ = try await runProcess(executable: dockerPath, arguments: arguments)
            return DockerActionResult(
                container: trimmed,
                action: action,
                success: true,
                message: nil,
                collectedAt: Date()
            )
        } catch {
            return DockerActionResult(
                container: trimmed,
                action: action,
                success: false,
                message: error.localizedDescription,
                collectedAt: Date()
            )
        }
    }

    private func parseLine(_ line: Substring) -> DockerContainer? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return nil }

        return DockerContainer(
            id: String(parts[0]),
            name: String(parts[1]),
            status: String(parts[2]),
            state: String(parts[3])
        )
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let message = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: DockerMonitorError.commandFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public enum DockerMonitorError: LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output.isEmpty ? "Docker command failed" : output
        }
    }
}
