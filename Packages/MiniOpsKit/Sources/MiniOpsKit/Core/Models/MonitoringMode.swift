import Foundation

public enum MonitoringMode: String, Codable, CaseIterable, Sendable {
    case agent
    case client

    public var displayName: String {
        switch self {
        case .agent: return "서버 (에이전트)"
        case .client: return "원격 서버 조회"
        }
    }

    public var description: String {
        switch self {
        case .agent:
            return "miniopsd에서 사용합니다. CPU/Memory/Disk/Docker 수집과 LAN API를 제공합니다."
        case .client:
            return "같은 Wi‑Fi(LAN)에 있는 Mac Mini 서버(miniopsd) API에서 상태를 가져옵니다."
        }
    }
}
