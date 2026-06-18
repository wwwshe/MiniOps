import SwiftUI
import AppKit
import MiniOpsKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var monitoringService: MonitoringService
    @Bindable var settings: AppSettings

    @State private var isMetricsExpanded = true
    @State private var isDockerExpanded = true
    @State private var isHealthExpanded = true
    @State private var showStoppedContainers = false
    @State private var dockerActionMessage: String?
    @State private var pendingDockerAction: DockerActionConfirmation?

    private struct DockerActionConfirmation: Identifiable {
        let id = UUID()
        let containerName: String
        let action: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader
            summaryLine

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

            if let dockerActionMessage {
                Text(dockerActionMessage)
                    .font(.caption2)
                    .foregroundStyle(dockerActionMessage.hasPrefix("✓") ? .green : .red)
            }

            Divider()
            actionButtons
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            monitoringService.isMenuBarVisible = true
            Task { await monitoringService.refreshMetricsHistory() }
        }
        .onDisappear {
            monitoringService.isMenuBarVisible = false
        }
        .confirmationDialog(
            pendingDockerAction?.action == "stop" ? "컨테이너 중지" : "컨테이너 재시작",
            isPresented: Binding(
                get: { pendingDockerAction != nil },
                set: { if !$0 { pendingDockerAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingDockerAction {
                Button(action.action == "stop" ? "중지" : "재시작", role: action.action == "stop" ? .destructive : nil) {
                    Task { await performDockerAction(action) }
                }
                Button("취소", role: .cancel) { pendingDockerAction = nil }
            }
        } message: {
            if let action = pendingDockerAction {
                Text("\(action.containerName) 컨테이너를 \(action.action == "stop" ? "중지" : "재시작")할까요?")
            }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text("MiniOps — \(monitoringService.snapshot.overall.displayName)")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 4) {
                Image(systemName: "network").font(.caption2)
                Text(monitoringService.displaySourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(monitoringService.lastUpdatedDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryLine: some View {
        let docker = monitoringService.snapshot.dockerSummary
        let metrics = monitoringService.snapshot.metrics
        return Text("Docker \(docker.running)/\(docker.total) · CPU \(Int(metrics.cpuUsagePercent))% · Mem \(Int(metrics.memoryUsagePercent))% · Disk \(Int(metrics.diskUsagePercent))%")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var statusColor: Color {
        if monitoringService.connectionError != nil { return .gray }
        switch monitoringService.snapshot.overall {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "서버 시스템", isExpanded: $isMetricsExpanded)

            if isMetricsExpanded {
                metricRow(label: "CPU", value: monitoringService.snapshot.metrics.cpuUsagePercent)
                MetricsSparklineView(
                    points: monitoringService.metricsHistory,
                    keyPath: \.cpu,
                    color: .blue
                )
                metricRow(label: "Memory", value: monitoringService.snapshot.metrics.memoryUsagePercent)
                MetricsSparklineView(
                    points: monitoringService.metricsHistory,
                    keyPath: \.memory,
                    color: .purple
                )
                metricRow(label: "Disk", value: monitoringService.snapshot.metrics.diskUsagePercent)
                MetricsSparklineView(
                    points: monitoringService.metricsHistory,
                    keyPath: \.disk,
                    color: .orange
                )
            }
        }
    }

    private func sectionHeader(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func metricRow(label: String, value: Double) -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .leading)
            ProgressView(value: min(value, 100), total: 100)
            Text(String(format: "%.0f%%", value))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .font(.caption)
    }

    private var sortedContainers: [DockerContainer] {
        let containers = monitoringService.snapshot.docker.containers
        let running = containers.filter(\.isRunning).sorted { $0.name < $1.name }
        let stopped = containers.filter { !$0.isRunning }.sorted { $0.name < $1.name }
        return running + (showStoppedContainers ? stopped : [])
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "Docker", isExpanded: $isDockerExpanded)

            if isDockerExpanded {
                if !monitoringService.snapshot.docker.isAvailable {
                    Text(monitoringService.snapshot.docker.errorMessage ?? "Docker unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if monitoringService.snapshot.docker.containers.isEmpty {
                    Text("컨테이너 없음").font(.caption).foregroundStyle(.secondary)
                } else {
                    let stoppedCount = monitoringService.snapshot.docker.containers.filter { !$0.isRunning }.count
                    if stoppedCount > 0 {
                        Button(showStoppedContainers ? "중지됨 숨기기 (\(stoppedCount))" : "중지됨 보기 (\(stoppedCount))") {
                            showStoppedContainers.toggle()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                    }

                    ForEach(sortedContainers) { container in
                        dockerRow(container)
                    }
                }
            }
        }
    }

    private func dockerRow(_ container: DockerContainer) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(container.isRunning ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(container.name)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { openLogs(container) }

            Spacer()

            Menu {
                Button("로그 보기") { openLogs(container) }
                Button("재시작") {
                    pendingDockerAction = DockerActionConfirmation(containerName: container.name, action: "restart")
                }
                Button("중지", role: .destructive) {
                    pendingDockerAction = DockerActionConfirmation(containerName: container.name, action: "stop")
                }
            } label: {
                Text("로그")
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text(container.displayStatus)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var healthCheckSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "Health Check", isExpanded: $isHealthExpanded)

            if isHealthExpanded {
                ForEach(monitoringService.snapshot.healthChecks) { check in
                    HStack(alignment: .top) {
                        Circle()
                            .fill(check.isHealthy ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name).font(.caption.weight(.medium))
                            if let ms = check.responseTimeMs {
                                Text("\(ms)ms").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let error = check.lastError, !check.isHealthy {
                                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                        Spacer()
                    }
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

    private func openLogs(_ container: DockerContainer) {
        openWindow(id: "docker-logs", value: DockerLogRequest(containerName: container.name))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func performDockerAction(_ action: DockerActionConfirmation) async {
        pendingDockerAction = nil
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = RemoteSettingsClient()

        do {
            let response: APIDockerActionResponse
            if action.action == "restart" {
                response = try await client.restartDockerContainer(baseURL: baseURL, token: token, container: action.containerName)
            } else {
                response = try await client.stopDockerContainer(baseURL: baseURL, token: token, container: action.containerName)
            }
            dockerActionMessage = response.success
                ? "✓ \(action.containerName) \(action.action == "restart" ? "재시작" : "중지") 완료"
                : "✗ \(response.message ?? "실패")"
            monitoringService.restart()
        } catch {
            dockerActionMessage = "✗ \(error.localizedDescription)"
        }
    }
}
