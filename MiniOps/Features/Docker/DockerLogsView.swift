import SwiftUI
import MiniOpsKit

struct DockerLogsView: View {
    let request: DockerLogRequest
    @Bindable var settings: AppSettings

    @State private var logs = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var tail = 200

    private let tailOptions = [100, 200, 500, 1000]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.containerName)
                        .font(.headline)
                    Text("맥미니 서버 Docker 로그")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("줄 수", selection: $tail) {
                    ForEach(tailOptions, id: \.self) { count in
                        Text("최근 \(count)줄").tag(count)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: tail) { _, _ in
                    Task { await loadLogs() }
                }

                Button("새로고침") {
                    Task { await loadLogs() }
                }
                .disabled(isLoading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Group {
                if isLoading && logs.isEmpty {
                    ProgressView("로그 불러오는 중…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if logs.isEmpty {
                    ContentUnavailableView(
                        "로그 없음",
                        systemImage: "doc.text",
                        description: Text(errorMessage == nil ? "컨테이너 로그가 비어 있습니다." : "로그를 가져오지 못했습니다.")
                    )
                } else {
                    ScrollView {
                        Text(logs)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
        .task(id: "\(request.containerName)-\(tail)") {
            await loadLogs()
        }
    }

    private func loadLogs() async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !token.isEmpty else {
            errorMessage = "서버 URL과 API Token을 설정하세요."
            logs = ""
            return
        }

        isLoading = true
        defer { isLoading = false }

        let client = RemoteSettingsClient()
        do {
            let response = try await client.fetchDockerLogs(
                baseURL: baseURL,
                token: token,
                container: request.containerName,
                tail: tail
            )
            logs = response.logs
            errorMessage = response.errorMessage
        } catch {
            logs = ""
            errorMessage = error.localizedDescription
        }
    }
}
