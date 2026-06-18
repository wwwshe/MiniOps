import Foundation

public actor DockerLogWatcher {
    private var lastCheckedAt: [String: Date] = [:]

    // 감지할 키워드 (대소문자 구분)
    private static let errorKeywords = ["ERROR", "Error", "FATAL", "fatal", "PANIC", "panic", "exception", "Exception", "EXCEPTION"]
    private static let warnKeywords  = ["WARN", "Warn", "WARNING", "Warning"]

    public init() {}

    /// 실행 중인 컨테이너 목록을 받아 로그를 스캔하고 새 LogAlert 배열을 반환
    public func scan(containers: [DockerContainer], dockerPath: String) async -> [LogAlert] {
        guard FileManager.default.isExecutableFile(atPath: dockerPath) else { return [] }

        var alerts: [LogAlert] = []

        for container in containers where container.isRunning {
            let since = lastCheckedAt[container.name].map { sinceArg(from: $0) } ?? "60s"
            lastCheckedAt[container.name] = Date()

            guard let output = try? await runLogs(container: container.name, since: since, dockerPath: dockerPath),
                  !output.isEmpty else { continue }

            for line in output.split(whereSeparator: \.isNewline) {
                let text = String(line)
                if let level = detectLevel(in: text) {
                    alerts.append(LogAlert(
                        container: container.name,
                        level: level,
                        message: String(text.prefix(200))
                    ))
                }
            }
        }

        // 컨테이너가 사라지면 타임스탬프 정리
        let running = Set(containers.filter(\.isRunning).map(\.name))
        lastCheckedAt = lastCheckedAt.filter { running.contains($0.key) }

        return alerts
    }

    // MARK: - Private

    private func sinceArg(from date: Date) -> String {
        // docker --since 에 ISO8601 timestamp 전달
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func detectLevel(in line: String) -> LogAlert.LogAlertLevel? {
        for kw in Self.errorKeywords where line.contains(kw) { return .error }
        for kw in Self.warnKeywords  where line.contains(kw) { return .warn  }
        return nil
    }

    private func runLogs(container: String, since: String, dockerPath: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: dockerPath)
            process.arguments = ["logs", "--since", since, container]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { _ in
                // docker logs는 stderr로도 출력하므로 둘 다 합침
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: stdout + stderr)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
