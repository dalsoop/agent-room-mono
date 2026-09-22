import Foundation

/// 훅용 `check --cmd`. `ROOM_ID` 가 없으면 통과. 방 안이면 우회 패턴을 막는다.
public struct RoomCommandCheck: Sendable {
    public static let roomIDKey = "ROOM_ID"
    public static let agentTool = "Agent"
    public static let childOpenHint = "agent-room-terminal open <child>"

    public enum Verdict: Equatable, Sendable {
        case allow
        case deny(String)
    }

    public static func evaluate(
        command: String,
        tool: String?,
        environment: [String: String]
    ) -> Verdict {
        let roomID = environment[roomIDKey] ?? ""
        if roomID.isEmpty { return .allow }
        if tool == agentTool {
            return .deny("tool Agent is blocked in a room; \(childOpenHint)")
        }
        if let reason = blockReason(command) {
            return .deny(reason)
        }
        return .allow
    }

    public static func blockReason(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if hasEnvPathOverride(trimmed) {
            return "env PATH= is blocked inside a room"
        }
        let execTokens = executableTokens(in: trimmed)
        if let abs = execTokens.first(where: { $0.hasPrefix("/") }) {
            return "absolute path is blocked: \(abs)"
        }
        let tokens = splitTokens(trimmed)
        if let shell = shellDashC(tokens) {
            return "\(shell) -c is blocked inside a room"
        }
        if tokens.contains(where: isPython3) {
            return "python3 is blocked inside a room"
        }
        return nil
    }

    static func hasEnvPathOverride(_ command: String) -> Bool {
        let tokens = splitTokens(command)
        guard tokens.first == "env" else { return false }
        return tokens.dropFirst().contains { $0.hasPrefix("PATH=") }
    }

    static func shellDashC(_ tokens: [String]) -> String? {
        let shells = Set(["sh", "bash", "zsh"])
        var index = 0
        while index + 1 < tokens.count {
            if shells.contains(baseName(tokens[index])), tokens[index + 1] == ["-", "c"].joined() {
                return baseName(tokens[index])
            }
            index += 1
        }
        return nil
    }

    static func isPython3(_ token: String) -> Bool {
        baseName(token) == "python3"
    }

    static func executableTokens(in command: String) -> [String] {
        let parts = splitOnConnectors(command)
        return parts.compactMap { piece in
            splitTokens(piece).first
        }
    }

    static func splitOnConnectors(_ command: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var index = command.startIndex
        while index < command.endIndex {
            if command[index] == ";" {
                pieces.append(current)
                current = ""
                index = command.index(after: index)
                continue
            }
            if hasConnector(command, index, "&&") || hasConnector(command, index, "||") {
                pieces.append(current)
                current = ""
                index = command.index(index, offsetBy: 2)
                continue
            }
            if command[index] == "|" {
                pieces.append(current)
                current = ""
                index = command.index(after: index)
                continue
            }
            current.append(command[index])
            index = command.index(after: index)
        }
        pieces.append(current)
        return pieces
    }

    static func hasConnector(_ command: String, _ index: String.Index, _ token: String) -> Bool {
        command[index...].hasPrefix(token)
    }

    static func splitTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func baseName(_ token: String) -> String {
        URL(fileURLWithPath: token).lastPathComponent
    }
}
