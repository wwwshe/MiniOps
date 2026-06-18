import SwiftUI
import MiniOpsKit

struct HealthCheckEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let target: HealthCheckTarget
    let isNew: Bool
    let onSave: (HealthCheckTarget) -> Void

    @State private var name: String
    @State private var urlString: String
    @State private var intervalSeconds: Int
    @State private var timeoutSeconds: Int
    @State private var expectedStatusCode: Int
    @State private var validationError: String?

    init(target: HealthCheckTarget, isNew: Bool, onSave: @escaping (HealthCheckTarget) -> Void) {
        self.target = target
        self.isNew = isNew
        self.onSave = onSave
        _name = State(initialValue: target.name)
        _urlString = State(initialValue: target.urlString)
        _intervalSeconds = State(initialValue: target.intervalSeconds)
        _timeoutSeconds = State(initialValue: target.timeoutSeconds)
        _expectedStatusCode = State(initialValue: target.expectedStatusCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Health Check 추가" : "Health Check 편집")
                .font(.title2.weight(.semibold))

            TextField("이름", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("URL", text: $urlString, prompt: Text("https://example.com/health"))
                .textFieldStyle(.roundedBorder)

            Stepper("간격: \(intervalSeconds)초", value: $intervalSeconds, in: 5...3600, step: 5)
            Stepper("타임아웃: \(timeoutSeconds)초", value: $timeoutSeconds, in: 1...120)
            Stepper("기대 HTTP 코드: \(expectedStatusCode)", value: $expectedStatusCode, in: 100...599)

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button(isNew ? "추가" : "저장") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationError = "이름을 입력하세요."
            return
        }

        guard URL(string: trimmedURL) != nil else {
            validationError = "올바른 URL을 입력하세요."
            return
        }

        validationError = nil
        let updated = HealthCheckTarget(
            id: target.id,
            name: trimmedName,
            urlString: trimmedURL,
            intervalSeconds: intervalSeconds,
            timeoutSeconds: timeoutSeconds,
            expectedStatusCode: expectedStatusCode
        )
        onSave(updated)
        dismiss()
    }
}
