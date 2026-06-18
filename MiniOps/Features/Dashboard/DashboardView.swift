import SwiftUI
import AppKit
import MiniOpsKit

struct DashboardView: View {
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
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statusHeader

                    if let error = monitoringService.connectionError {
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }

                    if monitoringService.isLoadingRemote && monitoringService.snapshot.updatedAt == .distantPast {
                        ProgressView("서버 연결 중…").font(.body)
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
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let msg = dockerActionMessage {
                toastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dockerActionMessage)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 16, height: 16)
            Text("MiniOps — \(monitoringService.snapshot.overall.displayName)")
                .font(.title.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(monitoringService.displaySourceName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(monitoringService.lastUpdatedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        if monitoringService.connectionError != nil { return .gray }
        switch monitoringService.snapshot.overall {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "시스템", isExpanded: $isMetricsExpanded)
            if isMetricsExpanded {
                metricRow(label: "CPU", value: monitoringService.snapshot.metrics.cpuUsagePercent)
                MetricsSparklineView(points: monitoringService.metricsHistory, keyPath: \.cpu, color: .blue)
                metricRow(label: "Memory", value: monitoringService.snapshot.metrics.memoryUsagePercent)
                MetricsSparklineView(points: monitoringService.metricsHistory, keyPath: \.memory, color: .purple)
                metricRow(label: "Disk", value: monitoringService.snapshot.metrics.diskUsagePercent)
                MetricsSparklineView(points: monitoringService.metricsHistory, keyPath: \.disk, color: .orange)
            }
        }
    }

    private func sectionHeader(title: String, isExpanded: Binding<Bool>) -> some View {
        Button { isExpanded.wrappedValue.toggle() } label: {
            HStack {
                Text(title).font(.title3).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.body).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func metricRow(label: String, value: Double) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            ProgressView(value: min(value, 100), total: 100)
            Text(String(format: "%.0f%%", value)).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
        .font(.title3)
    }

    // MARK: - Docker

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
                        .font(.body).foregroundStyle(.secondary)
                } else if monitoringService.snapshot.docker.containers.isEmpty {
                    Text("컨테이너 없음").font(.body).foregroundStyle(.secondary)
                } else {
                    let stoppedCount = monitoringService.snapshot.docker.containers.filter { !$0.isRunning }.count
                    if stoppedCount > 0 {
                        Button(showStoppedContainers ? "중지됨 숨기기 (\(stoppedCount))" : "중지됨 보기 (\(stoppedCount))") {
                            showStoppedContainers.toggle()
                        }
                        .font(.callout).buttonStyle(.plain)
                    }
                    ForEach(sortedContainers) { container in
                        dockerRow(container)
                    }
                }
            }
        }
    }

    private func dockerRow(_ container: DockerContainer) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(container.isRunning ? Color.green : Color.orange)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { openLogs(container) }

                if container.isRunning, let cpu = container.cpuPercent, let mem = container.memPercent {
                    HStack(spacing: 8) {
                        Text(String(format: "CPU %.1f%%", cpu))
                        Text(String(format: "Mem %.1f%%", mem))
                        if let usage = container.memUsage { Text(usage) }
                    }
                    .font(.body).foregroundStyle(.secondary)
                }
            }

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
                Text("로그").font(.body)
            }
            .menuStyle(.borderlessButton).fixedSize()

            if !container.isRunning {
                Text(container.displayStatus).foregroundStyle(.secondary)
            }
        }
        .font(.title3)
    }

    // MARK: - Health Check

    private var healthCheckSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(title: "Health Check", isExpanded: $isHealthExpanded)
            if isHealthExpanded {
                ForEach(monitoringService.snapshot.healthChecks) { check in
                    HStack(alignment: .top) {
                        Circle()
                            .fill(check.isHealthy ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name).font(.title3.weight(.medium))
                            if let ms = check.responseTimeMs {
                                Text("\(ms)ms").font(.body).foregroundStyle(.secondary)
                            }
                            if let error = check.lastError, !check.isHealthy {
                                Text(error).font(.body).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Toast

    private func toastView(message: String) -> some View {
        let isSuccess = message.hasPrefix("✓")
        return HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isSuccess ? .green : .red)
            Text(message)
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
    }

    // MARK: - Actions

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
        try? await Task.sleep(for: .seconds(3))
        dockerActionMessage = nil
    }
}
