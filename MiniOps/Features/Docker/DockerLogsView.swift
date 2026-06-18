import SwiftUI
import AppKit
import MiniOpsKit

struct DockerLogsView: View {
    let request: DockerLogRequest
    @Bindable var settings: AppSettings

    @State private var logs = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var tail = 200
    @State private var searchText = ""
    @State private var autoRefreshInterval = 0
    @State private var stickToBottom = true
    @State private var scrollPosition: String?

    private let tailOptions = [100, 200, 500, 1000]
    private let refreshOptions: [(label: String, seconds: Int)] = [
        ("끔", 0), ("5초", 5), ("10초", 10), ("30초", 30)
    ]

    private var filteredLogs: String {
        guard !searchText.isEmpty else { return logs }
        return logs
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            toolbar

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            logContent
        }
        .padding()
        .frame(minWidth: 680, minHeight: 460)
        .task(id: "\(request.containerName)-\(tail)") {
            await loadLogs()
        }
        .task(id: autoRefreshInterval) {
            guard autoRefreshInterval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(autoRefreshInterval))
                await loadLogs(silent: true)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.containerName).font(.headline)
                Text("맥미니 서버 Docker 로그").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField("검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

            Picker("줄 수", selection: $tail) {
                ForEach(tailOptions, id: \.self) { count in
                    Text("\(count)줄").tag(count)
                }
            }
            .labelsHidden()
            .frame(width: 90)
            .onChange(of: tail) { _, _ in Task { await loadLogs() } }

            Picker("자동", selection: $autoRefreshInterval) {
                ForEach(refreshOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .labelsHidden()
            .frame(width: 70)

            Toggle("맨 아래", isOn: $stickToBottom)
                .toggleStyle(.checkbox)
                .font(.caption)

            Button("새로고침") { Task { await loadLogs() } }
                .disabled(isLoading)

            Button("복사") { copyLogs() }
            Button("저장…") { saveLogs() }
        }
    }

    private var logContent: some View {
        Group {
            if isLoading && logs.isEmpty {
                ProgressView("로그 불러오는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredLogs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "로그 없음" : "검색 결과 없음",
                    systemImage: "doc.text"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(filteredLogs)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("log-bottom")
                    }
                    .onChange(of: filteredLogs) { _, _ in
                        guard stickToBottom else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("log-bottom", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadLogs(silent: Bool = false) async {
        let baseURL = settings.remoteServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.remoteServerToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !token.isEmpty else {
            errorMessage = "서버 URL과 API Token을 설정하세요."
            logs = ""
            return
        }

        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }

        do {
            let response = try await RemoteSettingsClient().fetchDockerLogs(
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

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filteredLogs, forType: .string)
    }

    private func saveLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(request.containerName)-logs.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? filteredLogs.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
