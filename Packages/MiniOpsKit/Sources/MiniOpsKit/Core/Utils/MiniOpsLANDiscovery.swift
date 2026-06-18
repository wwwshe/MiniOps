import Foundation
import Network

public struct DiscoveredMiniOpsServer: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let baseURL: String

    public init(id: String, name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

public enum MiniOpsBonjour {
    public static let serviceType = "_miniops._tcp"
}

public final class MiniOpsServerBrowser {
    public init() {}

    public func discover(timeout: TimeInterval = 5) async -> [DiscoveredMiniOpsServer] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.miniops.bonjour.browse")
            var servers: [DiscoveredMiniOpsServer] = []
            let lock = NSLock()
            var finished = false

            func complete() {
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    return
                }
                finished = true
                let result = servers
                lock.unlock()
                browser.cancel()
                continuation.resume(returning: result)
            }

            let parameters = NWParameters()
            parameters.includePeerToPeer = true

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: MiniOpsBonjour.serviceType, domain: nil),
                using: parameters
            )

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    complete()
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case .service(let name, _, _, _) = result.endpoint else { continue }

                    Task {
                        guard let resolved = await Self.resolve(endpoint: result.endpoint),
                              let baseURL = Self.buildBaseURL(host: resolved.host, port: resolved.port) else {
                            return
                        }

                        let server = DiscoveredMiniOpsServer(
                            id: name,
                            name: name,
                            baseURL: baseURL
                        )

                        lock.lock()
                        if let index = servers.firstIndex(where: { $0.id == name }) {
                            let existing = servers[index]
                            if Self.hostPriority(resolved.host) > Self.hostPriority(Self.hostFromBaseURL(existing.baseURL)) {
                                servers[index] = server
                            }
                        } else {
                            servers.append(server)
                        }
                        lock.unlock()
                    }
                }
            }

            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout, execute: complete)
        }
    }

    private static func resolve(endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        if let ipv4 = await resolve(endpoint: endpoint, preferIPv4: true),
           isUsableLANHost(ipv4.host) {
            return ipv4
        }

        if let fallback = await resolve(endpoint: endpoint, preferIPv4: false),
           isUsableLANHost(fallback.host) {
            return fallback
        }

        return nil
    }

    private static func resolve(endpoint: NWEndpoint, preferIPv4: Bool) async -> (host: String, port: Int)? {
        await withCheckedContinuation { continuation in
            let parameters = NWParameters.tcp
            if preferIPv4,
               let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOptions.version = .v4
            }

            let connection = NWConnection(to: endpoint, using: parameters)
            var finished = false

            connection.stateUpdateHandler = { state in
                guard !finished else { return }

                switch state {
                case .ready:
                    finished = true
                    if let remote = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = remote {
                        continuation.resume(returning: (hostString(from: host), Int(port.rawValue)))
                    } else {
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    finished = true
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func hostString(from host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        case .name(let name, _):
            return name.hasSuffix(".") ? String(name.dropLast()) : name
        @unknown default:
            return "\(host)"
        }
    }

    private static func isUsableLANHost(_ host: String) -> Bool {
        let lower = host.lowercased()

        if lower.contains("%") {
            return false
        }

        if lower.hasPrefix("fe80:") || lower.hasPrefix("fe80::") {
            return false
        }

        if lower.hasSuffix(".local") {
            return true
        }

        return RemoteAPIURL.isLocalNetworkHost(host)
    }

    private static func buildBaseURL(host: String, port: Int) -> String? {
        guard isUsableLANHost(host) else { return nil }

        if host.contains(":") {
            return "http://[\(host)]:\(port)"
        }

        return "http://\(host):\(port)"
    }

    private static func hostFromBaseURL(_ baseURL: String) -> String {
        guard let components = URLComponents(string: baseURL) else { return "" }
        return components.host ?? ""
    }

    private static func hostPriority(_ host: String) -> Int {
        let lower = host.lowercased()
        if lower.split(separator: ".").count == 4, !lower.contains(":") {
            return 3
        }
        if lower.hasSuffix(".local") {
            return 2
        }
        return 1
    }
}
