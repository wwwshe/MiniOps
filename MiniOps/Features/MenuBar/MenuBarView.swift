import SwiftUI
import AppKit
import MiniOpsKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var monitoringService: MonitoringService
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if let error = monitoringService.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            if monitoringService.isLoadingRemote && monitoringService.snapshot.updatedAt == .distantPast {
                ProgressView("서버 연결 중…")
                    .font(.caption)
            } else {
                Divider()

                metricsSection

                Divider()

                dockerSection

                if !monitoringService.snapshot.healthChecks.isEmpty {
                    Divider()
                    healthCheckSection
                }
            }

            Divider()

            actionButtons
        }
        .padding(12)
        .frame(width: 320)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text("MiniOps — \(monitoringService.snapshot.overall.displayName)")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 4) {
                Image(systemName: settings.isClientMode ? "network" : "desktopcomputer")
                    .font(.caption2)
                Text(monitoringService.displaySourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.isClientMode ? "서버 시스템" : "시스템")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            metricRow(label: "CPU", value: monitoringService.snapshot.metrics.cpuUsagePercent)
            metricRow(label: "Memory", value: monitoringService.snapshot.metrics.memoryUsagePercent)
            metricRow(label: "Disk", value: monitoringService.snapshot.metrics.diskUsagePercent)
        }
    }

    private func metricRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .frame(width: 60, alignment: .leading)
            ProgressView(value: min(value, 100), total: 100)
            Text(String(format: "%.0f%%", value))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .font(.caption)
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Docker")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !monitoringService.snapshot.docker.isAvailable {
                Text(monitoringService.snapshot.docker.errorMessage ?? "Docker unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if monitoringService.snapshot.docker.containers.isEmpty {
                Text("컨테이너 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monitoringService.snapshot.docker.containers) { container in
                    HStack {
                        Circle()
                            .fill(container.isRunning ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(container.name)
                            .lineLimit(1)
                        Spacer()
                        Text(container.displayStatus)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var healthCheckSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health Check")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(monitoringService.snapshot.healthChecks) { check in
                HStack(alignment: .top) {
                    Circle()
                        .fill(check.isHealthy ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.name)
                            .font(.caption.weight(.medium))
                        if let ms = check.responseTimeMs {
                            Text("\(ms)ms")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let error = check.lastError, !check.isHealthy {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("설정…") {
                SettingsWindowPresenter.openOrFocus(openWindow: openWindow)
            }
            Spacer()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
