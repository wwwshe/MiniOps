import SwiftUI
import MiniOpsKit

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var monitoringService: MonitoringService
    var onMonitoringRestart: () -> Void

    @State private var connectionTestResult: String?
    @State private var discoveredServers: [DiscoveredMiniOpsServer] = []
    @State private var isDiscovering = false
    @State private var discoveryMessage: String?
    @State private var discoveryMessageKind: DiscoveryMessageKind = .idle
    @State private var remoteDockerPath: String = ""
    @State private var remoteDockerStatus: String?

    private enum DiscoveryMessageKind {
        case idle
        case loading
        case success
        case failure
    }

    var body: some View {
        Form {
            Section {
                Text("맥미니 서버(miniopsd) 상태를 조회합니다. 서버는 Homebrew로 설치하세요: brew install miniops")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

                if let discoveryMessage {
                    Text(discoveryMessage)
                        .font(.caption)
                        .foregroundStyle(discoveryMessageColor)
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

            Section("원격 서버 Docker") {
                Text("불러오기로 맥미니에서 docker 경로를 찾고, 연결 테스트로 서버에 적용한 뒤 동작을 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let serverDockerError = monitoringService.snapshot.docker.errorMessage,
                   !monitoringService.snapshot.docker.isAvailable {
                    Text("서버 Docker: \(serverDockerError)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextField("Docker CLI 경로", text: $remoteDockerPath, prompt: Text("/usr/local/bin/docker"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("서버에서 불러오기") {
                        Task { await loadRemoteDockerPath() }
                    }
                    Button("연결 테스트") {
                        Task { await testRemoteDocker() }
                    }
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
        .frame(width: 520, height: 420)
    }

    private var discoveryMessageColor: Color {
        switch discoveryMessageKind {
        case .idle:
            return .secondary
        case .loading, .success:
            return .green
        case .failure:
            return .red
        }
    }

    private func normalizeRemoteURL() {
        guard let normalized = RemoteAPIURL.normalize(settings.remoteServerBaseURL)?.absoluteString else { return }
        settings.remoteServerBaseURL = normalized
    }

    private func loadRemoteDockerPath(silent: Bool = false) async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !token.isEmpty else {
            if !silent {
                remoteDockerStatus = "서버 URL과 API Token을 먼저 입력하세요."
            }
            return
        }

        let client = RemoteSettingsClient()
        do {
            let response = try await client.fetchSettings(baseURL: baseURL, token: token)

            if let detected = response.detectedDockerPath, !detected.isEmpty {
                remoteDockerPath = detected
                if !silent {
                    remoteDockerStatus = "✓ 서버에서 docker를 찾았습니다: \(detected)"
                }
            } else {
                remoteDockerPath = response.dockerPath
                if !silent {
                    remoteDockerStatus = "✗ 서버에서 docker를 찾지 못했습니다. Docker Desktop 실행 여부를 확인하세요."
                }
            }
        } catch {
            if !silent {
                remoteDockerStatus = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func testRemoteDocker() async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = remoteDockerPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !token.isEmpty else {
            remoteDockerStatus = "서버 URL과 API Token을 먼저 입력하세요."
            return
        }

        guard !path.isEmpty else {
            remoteDockerStatus = "Docker CLI 경로를 입력하거나 불러오기를 누르세요."
            return
        }

        let client = RemoteSettingsClient()
        do {
            let saved = try await client.updateDockerPath(baseURL: baseURL, token: token, dockerPath: path)
            remoteDockerPath = saved.dockerPath

            let docker: APIDockerResponse
            if let refreshed = saved.docker {
                docker = refreshed
            } else {
                docker = try await client.fetchDocker(baseURL: baseURL, token: token)
            }

            if docker.available {
                let count = docker.containers.count
                remoteDockerStatus = count > 0
                    ? "✓ Docker 연결 성공 (\(count)개 컨테이너)"
                    : "✓ Docker 연결 성공 (실행 중인 컨테이너 없음)"
            } else {
                remoteDockerStatus = "✗ \(docker.errorMessage ?? "Docker를 사용할 수 없습니다.")"
            }
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

        let browser = MiniOpsServerBrowser()
        let servers = await browser.discover(port: 8787)
        discoveredServers = servers

        if servers.count == 1, let server = servers.first {
            selectDiscoveredServer(server.baseURL)
            discoveryMessageKind = .success
            discoveryMessage = "서버 발견: \(server.baseURL)"
        } else if servers.isEmpty {
            discoveryMessageKind = .failure
            discoveryMessage = "서버를 찾지 못했습니다. miniopsd 실행·로컬 네트워크 권한을 확인하세요."
        } else {
            discoveryMessageKind = .success
            discoveryMessage = "\(servers.count)개 서버 발견 — 목록에서 선택하세요."
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
