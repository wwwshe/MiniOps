import SwiftUI
import MiniOpsKit

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var settings: AppSettings
    @Bindable var preferences: ClientPreferences
    var monitoringService: MonitoringService
    var onComplete: () -> Void

    @State private var step = 0
    @State private var pasteText = ""
    @State private var remoteDockerPath = ""
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var discoveredServers: [DiscoveredMiniOpsServer] = []

    private let totalSteps = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MiniOps 설정 마법사")
                .font(.title2.weight(.semibold))

            ProgressView(value: Double(step + 1), total: Double(totalSteps))
                .progressViewStyle(.linear)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: serverStep
                case 2: tokenStep
                case 3: dockerStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.hasPrefix("✓") ? .green : .red)
            }

            HStack {
                if step > 0 {
                    Button("이전") { step -= 1 }
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button("다음") { Task { await goNext() } }
                        .disabled(isWorking)
                } else {
                    Button("완료") { Task { await finish() } }
                        .disabled(isWorking)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 460)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("맥미니 서버를 모니터링합니다")
                .font(.headline)
            Text("맥미니에 miniopsd를 설치한 뒤, LAN URL과 API Token으로 연결합니다.")
                .foregroundStyle(.secondary)
            Text("1. 맥미니: brew install miniops && brew services start miniops")
            Text("2. 맥미니: miniopsd --print-config")
            Text("3. 이 Mac: 아래 단계에서 URL·Token 입력")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var serverStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("서버 찾기")
                .font(.headline)

            Button(isWorking ? "찾는 중…" : "LAN에서 서버 찾기") {
                Task { await discover() }
            }
            .disabled(isWorking)

            if !discoveredServers.isEmpty {
                Picker("발견된 서버", selection: $settings.remoteServerBaseURL) {
                    ForEach(discoveredServers) { server in
                        Text("\(server.name) — \(server.baseURL)").tag(server.baseURL)
                    }
                }
            }

            TextField("서버 URL", text: $settings.remoteServerBaseURL, prompt: Text("http://192.168.0.10:8787"))
                .textFieldStyle(.roundedBorder)

            TextField("서버 이름", text: $settings.remoteServerName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Token")
                .font(.headline)

            Text("맥미니에서 `miniopsd --print-config` 출력을 붙여넣으면 URL과 Token을 자동으로 채웁니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $pasteText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            Button("붙여넣기에서 가져오기") {
                let parsed = ServerConfigPasteParser.parse(pasteText)
                if let url = parsed.url { settings.remoteServerBaseURL = url }
                if let token = parsed.token { settings.remoteServerToken = token }
                statusMessage = parsed.url != nil || parsed.token != nil ? "✓ 설정을 가져왔습니다." : "✗ lan_url 또는 api_token을 찾지 못했습니다."
            }

            SecureField("API Token", text: $settings.remoteServerToken)
                .textFieldStyle(.roundedBorder)

            Button("연결 테스트") {
                Task { await testConnection() }
            }
            .disabled(isWorking)
        }
    }

    private var dockerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Docker (선택)")
                .font(.headline)

            TextField("Docker CLI 경로", text: $remoteDockerPath, prompt: Text("/usr/local/bin/docker"))
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("서버에서 불러오기") { Task { await loadDockerPath() } }
                Button("연결 테스트") { Task { await testDocker() } }
            }
            .disabled(isWorking)
        }
    }

    private func goNext() async {
        if step == 1 {
            if let normalized = RemoteAPIURL.normalize(settings.remoteServerBaseURL)?.absoluteString {
                settings.remoteServerBaseURL = normalized
            }
        }
        if step == 2 {
            await testConnection()
            guard statusMessage?.hasPrefix("✓") == true else { return }
        }
        step += 1
    }

    private func finish() async {
        if !remoteDockerPath.isEmpty {
            await testDocker()
        }
        preferences.onboardingCompleted = true
        monitoringService.restart()
        onComplete()
        dismiss()
    }

    private func discover() async {
        isWorking = true
        defer { isWorking = false }
        discoveredServers = await MiniOpsServerBrowser().discover(port: 8787)
        if let first = discoveredServers.first, settings.remoteServerBaseURL.isEmpty {
            settings.remoteServerBaseURL = first.baseURL
            settings.remoteServerName = first.name
        }
        statusMessage = discoveredServers.isEmpty ? "✗ 서버를 찾지 못했습니다." : "✓ \(discoveredServers.count)개 서버 발견"
    }

    private func testConnection() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await RemoteMonitoringClient().fetchSnapshot(
                baseURL: settings.remoteServerBaseURL,
                token: settings.remoteServerToken
            )
            statusMessage = "✓ 연결 성공"
        } catch {
            statusMessage = "✗ \(error.localizedDescription)"
        }
    }

    private func loadDockerPath() async {
        isWorking = true
        defer { isWorking = false }
        let client = RemoteSettingsClient()
        do {
            let response = try await client.fetchSettings(
                baseURL: settings.remoteServerBaseURL,
                token: settings.remoteServerToken
            )
            remoteDockerPath = response.detectedDockerPath ?? response.dockerPath
            statusMessage = "✓ Docker 경로를 불러왔습니다."
        } catch {
            statusMessage = "✗ \(error.localizedDescription)"
        }
    }

    private func testDocker() async {
        guard !remoteDockerPath.isEmpty else {
            statusMessage = "Docker 경로를 입력하거나 불러오세요."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let client = RemoteSettingsClient()
        do {
            _ = try await client.updateDockerPath(
                baseURL: settings.remoteServerBaseURL,
                token: settings.remoteServerToken,
                dockerPath: remoteDockerPath
            )
            statusMessage = "✓ Docker 연결 성공"
        } catch {
            statusMessage = "✗ \(error.localizedDescription)"
        }
    }
}
