import Foundation

/// `~/.codex/sessions` 세션 파일의 usage 합산. 경로는 호출자가 넘긴다.
public struct CodexUsageAdapter: UsageAdapter {
    public var tool: AgentRoomTool { .codex }

    public init() {}

    public func measure(file: URL) -> UsageReading {
        guard let lines = UsageJSONL.objects(from: file) else {
            return .unknown(tool: tool)
        }
        var input = 0
        var output = 0
        var requests = 0
        for line in lines {
            guard let usage = codexUsage(in: line) else { continue }
            input += UsageJSONL.int(usage, keys: ["input_tokens", "inputTokens"])
            input += UsageJSONL.int(usage, keys: ["cached_input_tokens", "cachedInputTokens"])
            output += UsageJSONL.int(usage, keys: ["output_tokens", "outputTokens"])
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

    private func codexUsage(in line: JSONValue) -> JSONValue? {
        if let direct = line.object?["usage"] { return direct }
        guard let payload = line.object?["payload"]?.object else { return nil }
        if let usage = payload["usage"] { return usage }
        let type = payload["type"]?.string
        guard type == "token_count" else { return nil }
        let info = payload["info"]?.object
        return info?["last_token_usage"] ?? info?["lastTokenUsage"]
    }
}
