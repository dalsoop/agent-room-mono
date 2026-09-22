import Foundation

/// 훅이 주는 transcript JSONL 의 assistant `usage` 합산.
public struct ClaudeUsageAdapter: UsageAdapter {
    public var tool: AgentRoomTool { .claude }

    public init() {}

    public func measure(file: URL) -> UsageReading {
        guard let lines = UsageJSONL.objects(from: file) else {
            return .unknown(tool: tool)
        }
        var input = 0
        var output = 0
        var requests = 0
        for line in lines {
            guard let usage = claudeUsage(in: line) else { continue }
            input += UsageJSONL.int(usage, keys: ["input_tokens"])
            input += UsageJSONL.int(usage, keys: ["cache_read_input_tokens"])
            output += UsageJSONL.int(usage, keys: ["output_tokens"])
            requests += 1
        }
        if requests == 0 { return .unknown(tool: tool) }
        return UsageReading(
            tool: tool,
            inputTokens: input,
            outputTokens: output,
            requests: requests,
            unknown: false,
            estimated: false
        )
    }

    private func claudeUsage(in line: JSONValue) -> JSONValue? {
        guard let object = line.object else { return nil }
        let message = object["message"]
        let type = object["type"]?.string
        let role = message?.object?["role"]?.string
        let isAssistant = type == "assistant" || role == "assistant"
        if !isAssistant { return nil }
        return message?.object?["usage"]
    }
}
