import SwiftUI
import MiniOpsKit

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var monitoringService: MonitoringService
    var onAPIServerRestart: () -> Void
    var onMonitoringRestart: () -> Void

    @State private var showAddHealthCheck = false
    @State private var editingTarget: HealthCheckTarget?
    @State private var connectionTestResult: String?
    @State private var discoveredServers: [DiscoveredMiniOpsServer] = []
    @State private var isDiscovering = false

    private var lanBaseURL: String? {
        LocalNetworkAddress.apiBaseURL(port: settings.apiPort)
    }

    var body: some View {
        TabView {
            serverTab
                .tabItem { Label("서버", systemImage: "server.rack") }
            healthCheckTab
                .tabItem { Label("Health Check", systemImage: "heart.text.square") }
                .disabled(settings.isClientMode)
            apiTab
                .tabItem { Label("API", systemImage: "network") }
                .disabled(settings.isClientMode)
        }
        .frame(width: 520, height: 480)
        .sheet(isPresented: $showAddHealthCheck) {
            HealthCheckEditorView(
                target: HealthCheckTarget(name: "", urlString: "https://"),
                isNew: true
            ) { target in
                settings.addHealthCheck(target)
                monitoringService.restartHealthChecks()
            }
        }
        .sheet(item: $editingTarget) { target in
            HealthCheckEditorView(target: target, isNew: false) { updated in
                settings.updateHealthCheck(updated)
                monitoringService.restartHealthChecks()
            }
        }
    }

    private var serverTab: some View {
        Form {
            Section("모니터링 모드") {
                Picker("모드", selection: $settings.monitoringMode) {
                    ForEach(MonitoringMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.monitoringMode) { _, _ in
                    onMonitoringRestart()
                    onAPIServerRestart()
                }

                Text(settings.monitoringMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.isClientMode {
                Section("원격 서버 (같은 Wi‑Fi)") {
                    Text("같은 Wi‑Fi의 Mac Mini를 찾거나, LAN URL과 API Token을 입력하세요. URL은 반드시 http:// 입니다 (HTTPS 아님).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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

                    TextField("서버 이름", text: $settings.remoteServerName)
                        .textFieldStyle(.roundedBorder)

                    TextField("서버 URL", text: $settings.remoteServerBaseURL, prompt: Text("http://192.168.0.10:8787"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { normalizeRemoteURL() }

                    SecureField("API Token", text: $settings.remoteServerToken)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("연결 테스트") {
                            Task { await testConnection() }
                        }
                        if let connectionTestResult {
                            Text(connectionTestResult)
                                .font(.caption)
                                .foregroundStyle(connectionTestResult.hasPrefix("✓") ? .green : .red)
                        }
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
            } else {
                Section("Docker") {
                    TextField("Docker CLI 경로", text: $settings.dockerPath)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var healthCheckTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Check는 서버(에이전트)에서 설정합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("등록된 Health Check")
                    .font(.headline)
                Spacer()
                Button("추가") { showAddHealthCheck = true }
            }

            if settings.healthCheckTargets.isEmpty {
                ContentUnavailableView(
                    "Health Check 없음",
                    systemImage: "heart.slash",
                    description: Text("모니터링할 URL을 추가하세요.")
                )
            } else {
                List {
                    ForEach(settings.healthCheckTargets) { target in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(target.name)
                                    .font(.body.weight(.medium))
                                Text(target.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("편집") { editingTarget = target }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = settings.healthCheckTargets[index].id
                            settings.removeHealthCheck(id: id)
                        }
                        monitoringService.restartHealthChecks()
                    }
                }
            }
        }
        .padding()
    }

    private var apiTab: some View {
        Form {
            Section("LAN API (같은 Wi‑Fi)") {
                Text("같은 Wi‑Fi에 있는 다른 Mac/기기에서 이 URL로 서버 상태를 조회할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("API 서버 활성화", isOn: $settings.apiEnabled)
                    .onChange(of: settings.apiEnabled) { _, _ in onAPIServerRestart() }

                Stepper("포트: \(settings.apiPort)", value: $settings.apiPort, in: 1024...65535)
                    .onChange(of: settings.apiPort) { _, _ in onAPIServerRestart() }

                if let lanBaseURL {
                    LabeledContent("LAN URL") {
                        Text(lanBaseURL)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } else {
                    Text("LAN IP를 찾을 수 없습니다. Wi‑Fi( en0 ) 연결을 확인하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("API Token") {
                    Text(settings.apiToken)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Button("토큰 재발급") {
                    settings.regenerateAPIToken()
                }
            }

            Section("사용 예시") {
                if let lanBaseURL {
                    Text("curl -H \"Authorization: Bearer \(settings.apiToken.prefix(8))...\" \(lanBaseURL)/api/v1/status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("curl -H \"Authorization: Bearer <token>\" http://<lan-ip>:\(settings.apiPort)/api/v1/status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func normalizeRemoteURL() {
        guard let normalized = RemoteAPIURL.normalize(settings.remoteServerBaseURL)?.absoluteString else { return }
        settings.remoteServerBaseURL = normalized
    }

    private func discoverServers() async {
        isDiscovering = true
        connectionTestResult = "같은 Wi‑Fi에서 서버를 찾는 중…"
        defer { isDiscovering = false }

        let browser = MiniOpsServerBrowser()
        let servers = await browser.discover(port: 8787)
        discoveredServers = servers

        if servers.count == 1, let server = servers.first {
            selectDiscoveredServer(server.baseURL)
            connectionTestResult = "✓ 서버 발견: \(server.baseURL)"
        } else if servers.isEmpty {
            connectionTestResult = "✗ 서버를 찾지 못했습니다. URL을 직접 입력하거나 맥미니 miniopsd 재시작을 확인하세요."
        } else {
            connectionTestResult = "✓ \(servers.count)개 서버 발견 — 목록에서 선택하세요."
        }
    }

    private func selectDiscoveredServer(_ baseURL: String) {
        guard let server = discoveredServers.first(where: { $0.baseURL == baseURL }) else {
            settings.remoteServerBaseURL = baseURL
            onMonitoringRestart()
            return
        }
        settings.remoteServerBaseURL = server.baseURL
        if settings.remoteServerName.isEmpty || settings.remoteServerName == "Mac Mini Server" {
            settings.remoteServerName = server.name
        }
        onMonitoringRestart()
    }

    private func testConnection() async {
        normalizeRemoteURL()
        let client = RemoteMonitoringClient()
        do {
            _ = try await client.fetchSnapshot(
                baseURL: settings.remoteServerBaseURL,
                token: settings.remoteServerToken
            )
            connectionTestResult = "✓ 연결 성공"
            onMonitoringRestart()
        } catch {
            connectionTestResult = "✗ \(error.localizedDescription)"
        }
    }
}
