import SwiftUI
import MiniOpsKit

struct HealthCheckEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var urlString: String
    @State private var intervalSeconds: Int
    @State private var timeoutSeconds: Int
    @State private var expectedStatusCode: Int
    @State private var validationError: String?

    private let targetID: UUID
    private let isNew: Bool
    private let onSave: (HealthCheckTarget) -> Void

    init(target: HealthCheckTarget, isNew: Bool, onSave: @escaping (HealthCheckTarget) -> Void) {
        _name = State(initialValue: target.name)
        _urlString = State(initialValue: target.urlString)
        _intervalSeconds = State(initialValue: target.intervalSeconds)
        _timeoutSeconds = State(initialValue: target.timeoutSeconds)
        _expectedStatusCode = State(initialValue: target.expectedStatusCode)
        targetID = target.id
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Health Check 추가" : "Health Check 편집")
                .font(.title2.weight(.semibold))

            Form {
                TextField("이름", text: $name)
                TextField("URL", text: $urlString)
                Stepper("간격: \(intervalSeconds)초", value: $intervalSeconds, in: 5...3600, step: 5)
                Stepper("타임아웃: \(timeoutSeconds)초", value: $timeoutSeconds, in: 1...120)
                Stepper("기대 상태 코드: \(expectedStatusCode)", value: $expectedStatusCode, in: 100...599)
            }

            if let validationError {
                Text(validationError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationError = "이름을 입력하세요."
            return
        }

        guard URL(string: trimmedURL) != nil else {
            validationError = "유효한 URL을 입력하세요."
            return
        }

        if AppSettings.shared.isSelfReferencingHealthCheck(trimmedURL, apiPort: AppSettings.shared.apiPort) {
            validationError = "MiniOps API URL은 Health Check 대상으로 등록할 수 없습니다."
            return
        }

        let target = HealthCheckTarget(
            id: targetID,
            name: trimmedName,
            urlString: trimmedURL,
            intervalSeconds: intervalSeconds,
            timeoutSeconds: timeoutSeconds,
            expectedStatusCode: expectedStatusCode
        )

        onSave(target)
        dismiss()
    }
}
