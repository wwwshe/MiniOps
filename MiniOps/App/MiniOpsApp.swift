import SwiftUI
import AppKit
import MiniOpsKit

@main
struct MiniOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var monitoringService: MonitoringService
    @State private var settings = AppSettings.shared
    @State private var preferences = ClientPreferences.shared
    @State private var showOnboarding = false

    init() {
        AppSettings.shared.monitoringMode = .client

        let service = MonitoringService()
        AppContainer.monitoringService = service
        _monitoringService = State(initialValue: service)

        let prefs = ClientPreferences.shared
        let appSettings = AppSettings.shared
        _showOnboarding = State(initialValue: !prefs.onboardingCompleted && (
            appSettings.remoteServerBaseURL.isEmpty || appSettings.remoteServerToken.isEmpty
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitoringService: monitoringService, settings: settings)
                .background(WindowLauncher(showOnboarding: $showOnboarding))
        } label: {
            Image("ic_menu_bar")
                .resizable()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)

        Window("MiniOps 대시보드", id: "dashboard") {
            DashboardView(monitoringService: monitoringService, settings: settings)
                .onAppear { NSApp.setActivationPolicy(.regular) }
        }
        .defaultSize(width: 420, height: 560)

        Window("MiniOps 설정", id: "settings") {
            SettingsView(
                settings: settings,
                preferences: preferences,
                monitoringService: monitoringService,
                onMonitoringRestart: { monitoringService.restart() }
            )
            .onAppear { NSApp.setActivationPolicy(.regular) }
        }
        .defaultSize(width: 720, height: 620)
        .windowResizability(.contentSize)

        Window("MiniOps 시작하기", id: "onboarding") {
            OnboardingView(
                settings: settings,
                preferences: preferences,
                monitoringService: monitoringService
            ) {
                showOnboarding = false
            }
            .onAppear { NSApp.setActivationPolicy(.regular) }
        }
        .defaultSize(width: 560, height: 460)
        .windowResizability(.contentSize)

        WindowGroup(id: "docker-logs", for: DockerLogRequest.self) { $request in
            if let request {
                DockerLogsView(request: request, settings: settings)
                    .onAppear { NSApp.setActivationPolicy(.regular) }
            }
        }
        .defaultSize(width: 720, height: 480)
        .windowResizability(.contentSize)
    }

    private var statusColor: Color {
        if monitoringService.connectionError != nil { return .gray }
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
        NotificationMonitor.shared.requestAuthorizationIfNeeded()

        NotificationCenter.default.addObserver(
            forName: .openMiniOpsSettings,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                AppContainer.openSettings?()
                if let window = NSApp.windows.first(where: { SettingsWindowPresenter.isSettingsWindow($0) }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "," else {
                return event
            }
            NotificationCenter.default.post(name: .openMiniOpsSettings, object: nil)
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct WindowLauncher: View {
    @Environment(\.openWindow) private var openWindow
    @Binding var showOnboarding: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                AppContainer.openSettings = {
                    openWindow(id: "settings")
                }
                if showOnboarding {
                    openWindow(id: "onboarding")
                    showOnboarding = false
                }
            }
    }
}
