import Foundation

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

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: DockerMonitorError.commandFailed(output))
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
