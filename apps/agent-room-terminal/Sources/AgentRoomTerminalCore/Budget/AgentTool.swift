import Foundation

/// 방이 지원하는 에이전트 도구. 설계도 `agentTools` 와 같은 식별자.
public enum AgentRoomTool: String, Codable, Sendable, CaseIterable, Equatable {
    case claude
    case codex
    case grok
    case agy

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .agy: return "Antigravity (agy)"
        }
    }

    public static func normalizeName(_ rawName: String) -> AgentRoomTool? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "antigravity" {
            return .agy
        }
        return AgentRoomTool(rawValue: trimmed)
    }
}
