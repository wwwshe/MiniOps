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
                    Text("Mac Mini의 LAN IP와 API Token을 입력하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("서버 이름", text: $settings.remoteServerName)
                        .textFieldStyle(.roundedBorder)

                    TextField("서버 URL", text: $settings.remoteServerBaseURL, prompt: Text("http://192.168.0.10:8787"))
                        .textFieldStyle(.roundedBorder)

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
                .onChange(of: settings.remoteServerBaseURL) { _, _ in onMonitoringRestart() }
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

    private func testConnection() async {
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
