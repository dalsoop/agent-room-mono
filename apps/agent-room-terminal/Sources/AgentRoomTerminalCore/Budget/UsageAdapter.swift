import Foundation

/// 로컬 세션 기록 한 번의 측정. `unknown` 이면 추정하지 않는다.
public struct UsageReading: Equatable, Sendable {
    public var tool: AgentRoomTool
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int
    public var unknown: Bool
    public var estimated: Bool

    public init(
        tool: AgentRoomTool,
        inputTokens: Int,
        outputTokens: Int,
        requests: Int,
        unknown: Bool,
        estimated: Bool = false
    ) {
        self.tool = tool
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
        self.unknown = unknown
        self.estimated = estimated
    }

    public static func unknown(tool: AgentRoomTool) -> UsageReading {
        UsageReading(
            tool: tool,
            inputTokens: 0,
            outputTokens: 0,
            requests: 0,
            unknown: true,
            estimated: false
        )
    }
}

/// 도구별 사용량 어댑터. 네트워크·API 키를 쓰지 않고 로컬 파일만 읽는다.
public protocol UsageAdapter: Sendable {
    var tool: AgentRoomTool { get }
    func measure(file: URL) -> UsageReading
}

public enum UsageAdapters {
    public static func adapter(for tool: AgentRoomTool) -> any UsageAdapter {
        switch tool {
        case .claude: return ClaudeUsageAdapter()
        case .codex: return CodexUsageAdapter()
        case .grok: return GrokUsageAdapter()
        case .agy: return AgyUsageAdapter()
        }
    }
}

enum UsageJSONL {
    static func objects(from file: URL) -> [JSONValue]? {
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            return nil
        }
        var objects: [JSONValue] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            do {
                objects.append(try JSONDecoder().decode(JSONValue.self, from: data))
            } catch {
                continue
            }
        }
        return objects
    }

    static func int(_ value: JSONValue?, keys: [String]) -> Int {
        guard let object = value?.object else { return 0 }
        for key in keys {
            if let number = object[key]?.int { return number }
        }
        return 0
    }
}
