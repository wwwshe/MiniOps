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
            listener?.service = NWListener.Service(name: serviceName, type: MiniOpsBonjour.serviceType)
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

        guard let requestData = await readRequest(from: connection),
              let requestString = String(data: requestData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let request = parseRequest(requestString)
        let response = router.route(request: request)
        let responseData = buildHTTPResponse(response)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func readRequest(from connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let error {
                    print("MiniOps API: receive error — \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func parseRequest(_ raw: String) -> HTTPRequest {
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return HTTPRequest(method: "GET", path: "/", headers: [:])
        }

        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let path = parts.dropFirst().first.map { String($0.split(separator: "?").first ?? $0) } ?? "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let headerParts = line.split(separator: ":", maxSplits: 1)
            guard headerParts.count == 2 else { continue }
            let key = String(headerParts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(headerParts[1]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return HTTPRequest(method: method, path: path, headers: headers)
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
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}
