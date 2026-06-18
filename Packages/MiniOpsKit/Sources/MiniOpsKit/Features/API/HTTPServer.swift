import Foundation
import Network

@MainActor
public final class HTTPServer {
    private var listener: NWListener?
    private let router: APIRouter
    private let settings: AppSettings

    public init(router: APIRouter, settings: AppSettings = .shared) {
        self.router = router
        self.settings = settings
    }

    public func start() {
        guard settings.apiEnabled else {
            stop()
            return
        }

        stop()

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(settings.apiPort)))
            let serviceName = Host.current().localizedName ?? "MiniOps"
            listener?.service = NWListener.Service(
                name: serviceName,
                type: MiniOpsBonjour.serviceType,
                txtRecord: MiniOpsBonjour.txtRecord(port: settings.apiPort)
            )
        } catch {
            print("MiniOps API: failed to create listener — \(error)")
            return
        }

        listener?.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("MiniOps API: listener failed — \(error)")
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                await self?.handle(connection: connection)
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
        print("MiniOps API: listening on port \(settings.apiPort) (Bonjour: \(MiniOpsBonjour.serviceType))")
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public func restart() {
        start()
    }

    private func handle(connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))

        guard let requestData = await readRequest(from: connection) else {
            connection.cancel()
            return
        }

        let request = parseRequest(from: requestData)
        let response = router.route(request: request)
        let responseData = buildHTTPResponse(response)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func readRequest(from connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            var buffer = Data()

            func receiveNext() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let error {
                        print("MiniOps API: receive error — \(error)")
                        continuation.resume(returning: nil)
                        return
                    }

                    if let data {
                        buffer.append(data)
                    }

                    if Self.hasCompleteHTTPMessage(buffer) {
                        continuation.resume(returning: buffer)
                        return
                    }

                    if isComplete {
                        continuation.resume(returning: buffer.isEmpty ? nil : buffer)
                        return
                    }

                    receiveNext()
                }
            }

            receiveNext()
        }
    }

    private static func hasCompleteHTTPMessage(_ buffer: Data) -> Bool {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
                ?? buffer.range(of: Data("\n\n".utf8)) else {
            return false
        }

        let headerData = buffer[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return false
        }

        let expectedBodyLength = contentLength(from: headerString)
        let bodyStart = headerEnd.upperBound
        return buffer.count - bodyStart >= expectedBodyLength
    }

    private static func contentLength(from headerSection: String) -> Int {
        let lines = headerSection
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        for line in lines {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-length:") else { continue }
            let value = lower.dropFirst("content-length:".count)
                .trimmingCharacters(in: .whitespaces)
            return max(Int(value) ?? 0, 0)
        }
        return 0
    }

    private func parseRequest(from data: Data) -> HTTPRequest {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8))
                ?? data.range(of: Data("\n\n".utf8)),
              let headerString = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return HTTPRequest(method: "GET", path: "/", headers: [:], body: Data())
        }

        let headerLines = headerString.components(separatedBy: "\r\n")

        guard let requestLine = headerLines.first, !requestLine.isEmpty else {
            return HTTPRequest(method: "GET", path: "/", headers: [:], body: Data())
        }

        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let path = parts.dropFirst().first.map { String($0.split(separator: "?").first ?? $0) } ?? "/"

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() where !line.isEmpty {
            let headerParts = line.split(separator: ":", maxSplits: 1)
            guard headerParts.count == 2 else { continue }
            let key = String(headerParts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(headerParts[1]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let expectedBodyLength = Self.contentLength(from: headerString)
        var body = data[headerEnd.upperBound...]
        if expectedBodyLength > 0 {
            body = body.prefix(expectedBodyLength)
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body))
    }

    private func buildHTTPResponse(_ response: HTTPResponse) -> Data {
        let bodyString = String(data: response.body, encoding: .utf8) ?? ""
        let http = """
        HTTP/1.1 \(response.statusCode) \(statusText(for: response.statusCode))\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(bodyString.utf8.count)\r
        Connection: close\r
        \r
        \(bodyString)
        """
        return Data(http.utf8)
    }

    private func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}
