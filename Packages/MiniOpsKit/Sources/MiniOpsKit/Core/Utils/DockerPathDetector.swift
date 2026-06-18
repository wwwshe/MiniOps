import Foundation

public enum DockerPathDetector {
    private static let commonPaths = [
        "/opt/homebrew/bin/docker",
        "/usr/local/bin/docker",
        "/usr/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// `which docker` 및 일반적인 설치 경로에서 docker CLI를 찾습니다.
    public static func detect() -> String? {
        if let fromWhich = runWhich("docker") {
            return fromWhich
        }

        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private static func runWhich(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        var environment = ProcessInfo.processInfo.environment
        let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = environment["PATH"].map { "\(path):\($0)" } ?? path
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let output, !output.isEmpty,
                  FileManager.default.isExecutableFile(atPath: output) else {
                return nil
            }

            return output
        } catch {
            return nil
        }
    }
}
