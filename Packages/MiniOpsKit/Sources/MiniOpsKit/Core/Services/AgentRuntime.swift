import Foundation

@MainActor
public enum AgentRuntime {
    private static var monitoring: MonitoringService?
    private static var httpServer: HTTPServer?

    public static func start() {
        let settings = AppSettings.shared
        settings.monitoringMode = .agent

        let service = MonitoringService()
        let router = APIRouter(monitoringService: service)
        let server = HTTPServer(router: router)

        monitoring = service
        httpServer = server

        service.start()

        if settings.apiEnabled {
            server.start()
        }

        logStartup(settings: settings)
    }

    public static func stop() {
        monitoring?.stop()
        httpServer?.stop()
        monitoring = nil
        httpServer = nil
    }

    private static func logStartup(settings: AppSettings) {
        let port = settings.apiPort
        if let lan = LocalNetworkAddress.apiBaseURL(port: port) {
            fputs("MiniOps daemon listening on \(lan)\n", stderr)
        } else {
            fputs("MiniOps daemon listening on port \(port)\n", stderr)
        }
        fputs("API token: \(settings.apiToken)\n", stderr)
        fputs("Config: \(AppSettings.configDirectoryPath)\n", stderr)
    }
}
