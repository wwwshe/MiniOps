import Foundation

public enum APIAuthMiddleware {
    static func isAuthorized(request: HTTPRequest, expectedToken: String) -> Bool {
        guard let authHeader = request.headers["authorization"] else { return false }
        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else { return false }
        let token = String(authHeader.dropFirst(prefix.count))
        return token == expectedToken
    }
}

public struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
}

public struct HTTPResponse {
    let statusCode: Int
    let body: Data
    let contentType: String

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: status, body: data, contentType: "application/json")
    }

    static func text(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, body: Data(text.utf8), contentType: "text/plain")
    }

    static func unauthorized() -> HTTPResponse {
        .json(APIErrorResponse(error: "Unauthorized"), status: 401)
    }

    static func notFound() -> HTTPResponse {
        .json(APIErrorResponse(error: "Not Found"), status: 404)
    }
}

public struct APIErrorResponse: Codable {
    let error: String
}
