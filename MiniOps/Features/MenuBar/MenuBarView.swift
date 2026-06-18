import SwiftUI
import AppKit
import MiniOpsKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var monitoringService: MonitoringService
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            summaryLine

            if let error = monitoringService.connectionError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()
            actionButtons
        }
        .padding(14)
        .frame(width: 360)
        .onChange(of: monitoringService.snapshot.updatedAt) { _, _ in
            NotificationMonitor.shared.evaluate(monitoringService: monitoringService)
        }
        .onChange(of: monitoringService.connectionError) { _, _ in
            NotificationMonitor.shared.evaluate(monitoringService: monitoringService)
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text("MiniOps — \(monitoringService.snapshot.overall.displayName)")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 4) {
                    Image(systemName: "network").font(.subheadline)
                    Text(monitoringService.displaySourceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(monitoringService.lastUpdatedDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summaryLine: some View {
        let docker = monitoringService.snapshot.dockerSummary
        let metrics = monitoringService.snapshot.metrics
        return HStack(spacing: 16) {
            Label("Docker \(docker.running)/\(docker.total)", systemImage: "shippingbox")
            Label(String(format: "CPU %d%%", Int(metrics.cpuUsagePercent)), systemImage: "cpu")
            Label(String(format: "Mem %d%%", Int(metrics.memoryUsagePercent)), systemImage: "memorychip")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        if monitoringService.connectionError != nil { return .gray }
        switch monitoringService.snapshot.overall {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("대시보드") {
                openWindow(id: "dashboard")
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("설정") {
                SettingsWindowPresenter.openOrFocus(openWindow: openWindow)
            }
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.subheadline)
    }
}
