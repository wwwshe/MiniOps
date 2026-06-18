import Foundation
import MiniOpsKit

@main
struct MiniOpsDaemonMain {
    static func main() async {
        if CommandLine.arguments.contains("--print-token") {
            print(AppSettings.shared.apiToken)
            return
        }

        if CommandLine.arguments.contains("--print-config") {
            printConfig()
            return
        }

        if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
            printHelp()
            return
        }

        await runDaemon()
    }

    @MainActor
    private static func runDaemon() async {
        AgentRuntime.start()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                DaemonLifecycle.registerTerminationHandler {
                    Task { @MainActor in
                        AgentRuntime.stop()
                        fputs("MiniOps daemon stopped\n", stderr)
                        continuation.resume()
                    }
                }
                DaemonLifecycle.waitForTermination()
            }
        }
    }

    private static func printConfig() {
        let settings = AppSettings.shared
        let port = settings.apiPort
        let lan = LocalNetworkAddress.apiBaseURL(port: port) ?? "http://<lan-ip>:\(port)"
        print("""
        mode: agent
        api_enabled: \(settings.apiEnabled)
        api_port: \(port)
        lan_url: \(lan)
        api_token: \(settings.apiToken)
        docker_path: \(settings.dockerPath)
        config_dir: \(AppSettings.configDirectoryPath)
        """)
    }

    private static func printHelp() {
        print("""
        miniopsd — MiniOps server agent (headless)

        Usage:
          miniopsd              Run monitoring agent and HTTP API
          miniopsd --print-token   Print API token
          miniopsd --print-config  Print current configuration
          miniopsd --help          Show this help

        Install as service:
          brew tap wwwshe/miniops https://github.com/wwwshe/MiniOps.git
          brew trust wwwshe/miniops
          brew install miniops
          brew services start miniops
        """)
    }
}
