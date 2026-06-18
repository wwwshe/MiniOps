import Foundation

public enum RemoteAPIURL {
    /// LAN MiniOps API URL 정규화 (스킴 누락·https→http 보정, trailing slash 제거)
    public static func normalize(_ baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }

        guard var components = URLComponents(string: trimmed) else { return nil }

        if components.scheme == "https", isLocalNetworkHost(components.host) {
            components.scheme = "http"
        }

        if components.scheme == nil {
            components.scheme = "http"
        }

        guard let host = components.host, !host.isEmpty else { return nil }
        _ = host

        return components.url
    }

    public static func isLocalNetworkHost(_ host: String?) -> Bool {
        guard let host else { return false }

        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") {
            return true
        }

        if lower.hasPrefix("192.168.") || lower.hasPrefix("10.") {
            return true
        }

        if lower.hasPrefix("172.") {
            let parts = lower.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }

        if lower.hasPrefix("169.254.") {
            return true
        }

        return false
    }
}
