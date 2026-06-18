import SwiftUI
import AppKit
import MiniOpsKit

@main
struct MiniOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var monitoringService: MonitoringService
    @State private var settings = AppSettings.shared

    init() {
        AppSettings.shared.monitoringMode = .client

        let service = MonitoringService()
        AppContainer.monitoringService = service
        _monitoringService = State(initialValue: service)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitoringService: monitoringService)
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
                onMonitoringRestart: { monitoringService.restart() }
            )
            .onAppear {
                NSApp.setActivationPolicy(.regular)
            }
        }
        .defaultSize(width: 520, height: 420)
        .windowResizability(.contentSize)

        WindowGroup(id: "docker-logs", for: DockerLogRequest.self) { $request in
            if let request {
                DockerLogsView(request: request, settings: settings)
                    .onAppear {
                        NSApp.setActivationPolicy(.regular)
                    }
            }
        }
        .defaultSize(width: 720, height: 480)
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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppContainer.monitoringService?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
