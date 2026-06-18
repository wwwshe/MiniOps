import Foundation
import Darwin

public enum LocalNetworkAddress {
    /// Wi‑Fi/이더넷(en*) 인터페이스의 IPv4 주소 (예: 192.168.0.10)
    public static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var en0Address: String?
        var fallback: String?

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = String(cString: hostname)
            guard !ip.hasPrefix("127.") else { continue }

            if name == "en0" {
                en0Address = ip
            } else if fallback == nil {
                fallback = ip
            }
        }

        return en0Address ?? fallback
    }

    public static func apiBaseURL(port: Int) -> String? {
        guard let ip = primaryIPv4() else { return nil }
        return "http://\(ip):\(port)"
    }
}
