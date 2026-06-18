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

    public static func txtRecord(port: Int) -> NWTXTRecord {
        var txt = NWTXTRecord()
        if let ip = LocalNetworkAddress.primaryIPv4() {
            txt["ip"] = ip
        }
        txt["port"] = "\(port)"
        return txt
    }
}

public final class MiniOpsServerBrowser {
    public init() {}

    /// Bonjour 탐색 후, 실패 시 같은 서브넷에서 `/api/v1/health` 스캔
    public func discover(timeout: TimeInterval = 5, port: Int = 8787) async -> [DiscoveredMiniOpsServer] {
        let bonjour = await discoverBonjour(timeout: timeout)
        if !bonjour.isEmpty {
            return bonjour
        }
        return await discoverViaSubnetScan(port: port)
    }

    // MARK: - Bonjour

    private func discoverBonjour(timeout: TimeInterval) async -> [DiscoveredMiniOpsServer] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.miniops.bonjour.browse")
            var servers: [DiscoveredMiniOpsServer] = []
            var pendingResolves = 0
            var finished = false
            let lock = NSLock()

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: MiniOpsBonjour.serviceType, domain: nil),
                using: Self.browserParameters()
            )

            func finish() {
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

            func scheduleFinish() {
                queue.asyncAfter(deadline: .now() + timeout) {
                    lock.lock()
                    let pending = pendingResolves
                    lock.unlock()
                    if pending > 0 {
                        queue.asyncAfter(deadline: .now() + 2.0, execute: finish)
                    } else {
                        finish()
                    }
                }
            }

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    finish()
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if let server = Self.serverFromTXT(result) {
                        lock.lock()
                        Self.upsert(server, into: &servers)
                        lock.unlock()
                        continue
                    }

                    lock.lock()
                    pendingResolves += 1
                    lock.unlock()

                    Task {
                        defer {
                            lock.lock()
                            pendingResolves -= 1
                            lock.unlock()
                        }

                        guard let server = await Self.serverFromResolve(result) else { return }

                        lock.lock()
                        Self.upsert(server, into: &servers)
                        lock.unlock()
                    }
                }
            }

            browser.start(queue: queue)
            scheduleFinish()
        }
    }

    private static func browserParameters() -> NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func serverFromTXT(_ result: NWBrowser.Result) -> DiscoveredMiniOpsServer? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        guard case .bonjour(let txt) = result.metadata else { return nil }
        guard let ip = txt["ip"],
              let portString = txt["port"],
              let port = Int(portString),
              let baseURL = buildBaseURL(host: ip, port: port) else {
            return nil
        }

        return DiscoveredMiniOpsServer(id: name, name: name, baseURL: baseURL)
    }

    private static func serverFromResolve(_ result: NWBrowser.Result) async -> DiscoveredMiniOpsServer? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }

        guard let resolved = await resolve(endpoint: result.endpoint),
              let baseURL = buildBaseURL(host: resolved.host, port: resolved.port) else {
            return nil
        }

        return DiscoveredMiniOpsServer(id: name, name: name, baseURL: baseURL)
    }

    private static func upsert(_ server: DiscoveredMiniOpsServer, into servers: inout [DiscoveredMiniOpsServer]) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            let existing = servers[index]
            let newPriority = hostPriority(hostFromBaseURL(server.baseURL))
            let oldPriority = hostPriority(hostFromBaseURL(existing.baseURL))
            if newPriority >= oldPriority {
                servers[index] = server
            }
        } else {
            servers.append(server)
        }
    }

    // MARK: - Subnet scan (mDNS 실패 시 폴백)

    private func discoverViaSubnetScan(port: Int) async -> [DiscoveredMiniOpsServer] {
        guard let clientIP = LocalNetworkAddress.primaryIPv4() else { return [] }

        var octets = clientIP.split(separator: ".")
        guard octets.count == 4 else { return [] }
        octets.removeLast()
        let prefix = octets.joined(separator: ".")

        return await withTaskGroup(of: DiscoveredMiniOpsServer?.self) { group in
            for host in 1...254 {
                group.addTask {
                    await Self.probeHealthEndpoint(ip: "\(prefix).\(host)", port: port)
                }
            }

            var found: [DiscoveredMiniOpsServer] = []
            for await server in group {
                guard let server else { continue }
                if !found.contains(server) {
                    found.append(server)
                }
            }
            return found.sorted { $0.baseURL < $1.baseURL }
        }
    }

    private static func probeHealthEndpoint(ip: String, port: Int) async -> DiscoveredMiniOpsServer? {
        guard let url = URL(string: "http://\(ip):\(port)/api/v1/health") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.35

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let baseURL = "http://\(ip):\(port)"
            return DiscoveredMiniOpsServer(
                id: ip,
                name: "MiniOps (\(ip))",
                baseURL: baseURL
            )
        } catch {
            return nil
        }
    }

    // MARK: - Resolve

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
