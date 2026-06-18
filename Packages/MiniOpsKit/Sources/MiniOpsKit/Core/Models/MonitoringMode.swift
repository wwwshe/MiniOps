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
            return "이 Mac에서 직접 수집하고 API를 제공합니다. Mac Mini 서버에 설치할 때 사용하세요."
        case .client:
            return "같은 Wi‑Fi(LAN)에 있는 Mac Mini 서버의 API에서 상태를 가져옵니다."
        }
    }
}
