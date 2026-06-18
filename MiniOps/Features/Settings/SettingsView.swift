import SwiftUI
import MiniOpsKit

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var preferences: ClientPreferences
    @Bindable var monitoringService: MonitoringService
    var onMonitoringRestart: () -> Void

    @State private var connectionTestResult: String?
    @State private var discoveredServers: [DiscoveredMiniOpsServer] = []
    @State private var isDiscovering = false
    @State private var discoveryMessage: String?
    @State private var discoveryMessageKind: DiscoveryMessageKind = .idle
    @State private var remoteDockerPath: String = ""
    @State private var remoteDockerStatus: String?
    @State private var healthCheckTargets: [APIHealthCheckTargetItem] = []
    @State private var healthCheckStatus: String?
    @State private var showAddHealthCheck = false
    @State private var editingTarget: HealthCheckTarget?

    private enum DiscoveryMessageKind {
        case idle, loading, success, failure
    }

    var body: some View {
        TabView {
            connectionTab
                .tabItem { Label("서버", systemImage: "network") }
            dockerTab
                .tabItem { Label("Docker", systemImage: "shippingbox") }
            healthCheckTab
                .tabItem { Label("Health Check", systemImage: "heart.text.square") }
            notificationsTab
                .tabItem { Label("알림", systemImage: "bell") }
        }
        .frame(width: 560, height: 480)
        .sheet(isPresented: $showAddHealthCheck) {
            HealthCheckEditorView(
                target: HealthCheckTarget(name: "", urlString: "http://"),
                isNew: true
            ) { target in
                Task { await addHealthCheck(target) }
            }
        }
        .sheet(item: $editingTarget) { target in
            HealthCheckEditorView(target: target, isNew: false) { updated in
                Task { await addHealthCheck(updated) }
            }
        }
    }

    private var connectionTab: some View {
        Form {
            Section {
                Text("맥미니(miniopsd) API에 연결합니다. Token은 맥미니에서 `miniopsd --print-config`로 확인하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("원격 서버 (같은 Wi‑Fi)") {
                HStack {
                    Button(isDiscovering ? "찾는 중…" : "LAN에서 서버 찾기") {
                        Task { await discoverServers() }
                    }
                    .disabled(isDiscovering)

                    if !discoveredServers.isEmpty {
                        Picker("발견된 서버", selection: Binding(
                            get: { settings.remoteServerBaseURL },
                            set: { selectDiscoveredServer($0) }
                        )) {
                            Text("선택…").tag("")
                            ForEach(discoveredServers) { server in
                                Text("\(server.name) — \(server.baseURL)").tag(server.baseURL)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if let discoveryMessage {
                    Text(discoveryMessage)
                        .font(.caption)
                        .foregroundStyle(discoveryMessageColor)
                }

                TextField("서버 이름", text: $settings.remoteServerName)
                TextField("서버 URL", text: $settings.remoteServerBaseURL, prompt: Text("http://192.168.0.10:8787"))
                    .onSubmit { normalizeRemoteURL() }
                SecureField("API Token", text: $settings.remoteServerToken)

                HStack {
                    Button("연결 테스트") { Task { await testConnection() } }
                    if let connectionTestResult {
                        Text(connectionTestResult)
                            .font(.caption)
                            .foregroundStyle(connectionTestResult.hasPrefix("✓") ? .green : .red)
                    }
                }

                if connectionTestResult?.hasPrefix("✓") == true {
                    Text("연결되었습니다. 메뉴바 아이콘을 눌러 서버 상태를 확인하세요.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .onChange(of: settings.remoteServerBaseURL) { _, newValue in
                if let normalized = RemoteAPIURL.normalize(newValue)?.absoluteString,
                   normalized != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                    settings.remoteServerBaseURL = normalized
                }
                onMonitoringRestart()
            }
            .onChange(of: settings.remoteServerToken) { _, _ in onMonitoringRestart() }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var dockerTab: some View {
        Form {
            Section {
                Text("맥미니 서버의 Docker CLI 경로를 설정합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("원격 서버 Docker") {
                if let serverDockerError = monitoringService.snapshot.docker.errorMessage,
                   !monitoringService.snapshot.docker.isAvailable {
                    Text("서버 Docker: \(serverDockerError)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("Docker CLI 경로", text: $remoteDockerPath, prompt: Text("/usr/local/bin/docker"))

                HStack {
                    Button("서버에서 불러오기") { Task { await loadRemoteDockerPath() } }
                    Button("연결 테스트") { Task { await testRemoteDocker() } }
                }

                if let remoteDockerStatus {
                    Text(remoteDockerStatus)
                        .font(.caption)
                        .foregroundStyle(remoteDockerStatus.hasPrefix("✓") ? .green : .red)
                }
            }
            .task(id: settings.remoteServerBaseURL + settings.remoteServerToken) {
                await loadRemoteDockerPath(silent: true)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var healthCheckTab: some View {
        Form {
            Section {
                Text("맥미니 서버에서 주기적으로 외부 URL을 체크합니다. 실패 시 알림을 받을 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if healthCheckTargets.isEmpty {
                    ContentUnavailableView("등록된 Health Check 없음", systemImage: "heart.slash")
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(healthCheckTargets, id: \.id) { target in
                        HStack(spacing: 12) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name).font(.body.weight(.medium))
                                Text(target.url).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("매 \(target.intervalSeconds)초")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                editingTarget = target.asHealthCheckTarget
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                Task { await deleteHealthCheck(id: target.id) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("등록된 Health Check")
                    Spacer()
                    Button("새로고침") { Task { await loadHealthChecks() } }
                        .font(.caption)
                    Button("추가") { showAddHealthCheck = true }
                        .font(.caption)
                }
            } footer: {
                if let healthCheckStatus, healthCheckStatus.hasPrefix("✗") {
                    Text(healthCheckStatus)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await loadHealthChecks() }
    }

    private var notificationsTab: some View {
        Form {
            Section {
                Text("서버 상태가 임계치를 넘거나 Docker/Health Check에 문제가 생기면 macOS 알림을 보냅니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("알림") {
                Toggle("알림 사용", isOn: $preferences.notificationsEnabled)
                    .onChange(of: preferences.notificationsEnabled) { _, enabled in
                        if enabled { NotificationMonitor.shared.requestAuthorizationIfNeeded() }
                    }
                Toggle("경고 알림", isOn: $preferences.notifyOnWarning)
                Toggle("장애 알림", isOn: $preferences.notifyOnCritical)
            }

            Section("임계치 (%)") {
                Stepper("CPU: \(Int(preferences.cpuThreshold))%", value: $preferences.cpuThreshold, in: 50...100, step: 5)
                Stepper("Memory: \(Int(preferences.memoryThreshold))%", value: $preferences.memoryThreshold, in: 50...100, step: 5)
                Stepper("Disk: \(Int(preferences.diskThreshold))%", value: $preferences.diskThreshold, in: 50...100, step: 5)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var discoveryMessageColor: Color {
        switch discoveryMessageKind {
        case .idle: return .secondary
        case .loading, .success: return .green
        case .failure: return .red
        }
    }

    private func normalizeRemoteURL() {
        guard let normalized = RemoteAPIURL.normalize(settings.remoteServerBaseURL)?.absoluteString else { return }
        settings.remoteServerBaseURL = normalized
    }

    private func loadRemoteDockerPath(silent: Bool = false) async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !token.isEmpty else { return }

        let client = RemoteSettingsClient()
        do {
            let response = try await client.fetchSettings(baseURL: baseURL, token: token)
            remoteDockerPath = response.detectedDockerPath ?? response.dockerPath
            if !silent { remoteDockerStatus = "✓ Docker 경로 불러옴" }
        } catch {
            if !silent { remoteDockerStatus = "✗ \(error.localizedDescription)" }
        }
    }

    private func testRemoteDocker() async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = remoteDockerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !token.isEmpty, !path.isEmpty else {
            remoteDockerStatus = "URL, Token, Docker 경로를 입력하세요."
            return
        }

        let client = RemoteSettingsClient()
        do {
            let saved = try await client.updateDockerPath(baseURL: baseURL, token: token, dockerPath: path)
            remoteDockerPath = saved.dockerPath
            remoteDockerStatus = saved.docker?.available == true ? "✓ Docker 연결 성공" : "✗ Docker 사용 불가"
            onMonitoringRestart()
        } catch {
            remoteDockerStatus = "✗ \(error.localizedDescription)"
        }
    }

    private func discoverServers() async {
        isDiscovering = true
        discoveryMessageKind = .loading
        discoveryMessage = "같은 Wi‑Fi에서 서버를 찾는 중…"
        defer { isDiscovering = false }

        discoveredServers = await MiniOpsServerBrowser().discover(port: 8787)
        if discoveredServers.count == 1, let server = discoveredServers.first {
            selectDiscoveredServer(server.baseURL)
            discoveryMessageKind = .success
            discoveryMessage = "서버 발견: \(server.baseURL)"
        } else if discoveredServers.isEmpty {
            discoveryMessageKind = .failure
            discoveryMessage = "서버를 찾지 못했습니다."
        } else {
            discoveryMessageKind = .success
            discoveryMessage = "\(discoveredServers.count)개 서버 발견"
        }
    }

    private func selectDiscoveredServer(_ baseURL: String) {
        settings.remoteServerBaseURL = baseURL
        if let server = discoveredServers.first(where: { $0.baseURL == baseURL }) {
            settings.remoteServerName = server.name
        }
        onMonitoringRestart()
    }

    private func testConnection() async {
        normalizeRemoteURL()
        do {
            _ = try await RemoteMonitoringClient().fetchSnapshot(
                baseURL: settings.remoteServerBaseURL,
                token: settings.remoteServerToken
            )
            connectionTestResult = "✓ 연결 성공"
            onMonitoringRestart()
        } catch {
            connectionTestResult = "✗ \(error.localizedDescription)"
        }
    }

    private func loadHealthChecks() async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !token.isEmpty else {
            healthCheckStatus = "서버 URL과 Token을 먼저 설정하세요."
            return
        }

        do {
            let response = try await RemoteSettingsClient().fetchHealthCheckTargets(baseURL: baseURL, token: token)
            healthCheckTargets = response.targets
            healthCheckStatus = "✓ \(response.targets.count)개 Health Check"
        } catch {
            healthCheckStatus = "✗ \(error.localizedDescription)"
        }
    }

    private func addHealthCheck(_ target: HealthCheckTarget) async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = RemoteSettingsClient()
        let item = APIHealthCheckTargetItem(
            id: target.id.uuidString,
            name: target.name,
            url: target.urlString,
            intervalSeconds: target.intervalSeconds,
            timeoutSeconds: target.timeoutSeconds,
            expectedStatusCode: target.expectedStatusCode
        )

        do {
            // 기존 항목이면 먼저 삭제 후 재등록 (서버에 update API 없음)
            if healthCheckTargets.contains(where: { $0.id == target.id.uuidString }) {
                _ = try await client.deleteHealthCheckTarget(baseURL: baseURL, token: token, id: target.id)
            }
            let response = try await client.addHealthCheckTarget(baseURL: baseURL, token: token, target: item)
            healthCheckTargets = response.targets
            healthCheckStatus = "✓ Health Check 저장됨"
            onMonitoringRestart()
        } catch {
            healthCheckStatus = "✗ \(error.localizedDescription)"
        }
    }

    private func deleteHealthCheck(id: String) async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: id) else { return }

        do {
            let response = try await RemoteSettingsClient().deleteHealthCheckTarget(baseURL: baseURL, token: token, id: uuid)
            healthCheckTargets = response.targets
            healthCheckStatus = "✓ 삭제됨"
            onMonitoringRestart()
        } catch {
            healthCheckStatus = "✗ \(error.localizedDescription)"
        }
    }
}
