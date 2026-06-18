import SwiftUI
import AppKit
import MiniOpsKit

@main
struct MiniOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var monitoringService: MonitoringService
    @State private var settings = AppSettings.shared

    private let httpServer: HTTPServer

    init() {
        let service = MonitoringService()
        let router = APIRouter(monitoringService: service)
        let server = HTTPServer(router: router)

        AppContainer.monitoringService = service
        AppContainer.httpServer = server

        _monitoringService = State(initialValue: service)
        httpServer = server
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                monitoringService: monitoringService,
                settings: settings
            )
        } label: {
            Image(systemName: "server.rack")
                .symbolRenderingMode(.palette)
                .foregroundStyle(statusColor, .primary)
        }
        .menuBarExtraStyle(.window)

        Window("MiniOps 설정", id: "settings") {
            SettingsView(
                settings: settings,
                monitoringService: monitoringService,
                onAPIServerRestart: { restartAPIServer() },
                onMonitoringRestart: { monitoringService.restart() }
            )
            .onAppear {
                NSApp.setActivationPolicy(.regular)
            }
        }
        .defaultSize(width: 520, height: 480)
        .windowResizability(.contentSize)
    }

    private var statusColor: Color {
        if monitoringService.connectionError != nil {
            return .gray
        }
        switch monitoringService.snapshot.overall {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private func restartAPIServer() {
        if settings.isAgentMode && settings.apiEnabled {
            httpServer.restart()
        } else {
            httpServer.stop()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = AppSettings.shared
        AppContainer.monitoringService?.start()

        if settings.isAgentMode && settings.apiEnabled {
            AppContainer.httpServer?.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
