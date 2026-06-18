import Foundation

public enum RemoteSettingsError: LocalizedError {
    case invalidBaseURL
    case unauthorized
    case serverError(Int, String?)
    case decodingFailed
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "서버 URL이 올바르지 않습니다."
        case .unauthorized:
            return "API Token이 올바르지 않습니다."
        case .serverError(let code, let message):
            if let message, !message.isEmpty {
                return "서버 오류 (HTTP \(code)): \(message)"
            }
            return "서버 오류 (HTTP \(code))"
        case .decodingFailed:
            return "서버 응답을 해석할 수 없습니다."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

public final class RemoteSettingsClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func fetchSettings(baseURL: String, token: String) async throws -> APISettingsResponse {
        try await send(method: "GET", path: "/api/v1/settings", baseURL: baseURL, token: token, body: nil)
    }

    public func updateDockerPath(baseURL: String, token: String, dockerPath: String) async throws -> APISettingsResponse {
        let patch = APISettingsPatch(dockerPath: dockerPath)
        let body = try encoder.encode(patch)
        return try await send(method: "PATCH", path: "/api/v1/settings", baseURL: baseURL, token: token, body: body)
    }

    public func fetchDocker(baseURL: String, token: String) async throws -> APIDockerResponse {
        try await send(method: "GET", path: "/api/v1/docker", baseURL: baseURL, token: token, body: nil)
    }

    private func send<T: Decodable>(
        method: String,
        path: String,
        baseURL: String,
        token: String,
        body: Data?
    ) async throws -> T {
        guard let root = RemoteAPIURL.normalize(baseURL),
              let url = URL(string: path, relativeTo: root) else {
            throw RemoteSettingsError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = body

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteSettingsError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteSettingsError.serverError(0, nil)
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw RemoteSettingsError.unauthorized
        default:
            var message = (try? decoder.decode(APIErrorResponse.self, from: data))?.error
            if http.statusCode == 404 {
                message = "서버에 설정 API가 없습니다. 맥미니에서 brew upgrade miniops 후 재시작하세요."
            }
            throw RemoteSettingsError.serverError(http.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RemoteSettingsError.decodingFailed
        }
    }
}
