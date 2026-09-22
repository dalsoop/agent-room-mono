import Foundation

/// ACP 로그 봉투의 usage. 없으면 unknown — 추정하지 않는다.
public struct GrokUsageAdapter: UsageAdapter {
    public var tool: AgentRoomTool { .grok }

    public init() {}

    public func measure(file: URL) -> UsageReading {
        guard let lines = UsageJSONL.objects(from: file) else {
            return .unknown(tool: tool)
        }
        var input = 0
        var output = 0
        var requests = 0
        for line in lines {
            guard let usage = grokUsage(in: line) else { continue }
            input += UsageJSONL.int(usage, keys: ["inputTokens", "input_tokens"])
            input += UsageJSONL.int(usage, keys: ["cachedReadTokens", "cache_read_input_tokens"])
            output += UsageJSONL.int(usage, keys: ["outputTokens", "output_tokens"])
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

    private func grokUsage(in line: JSONValue) -> JSONValue? {
        let object = line.object
        if let update = object?["params"]?.object?["update"] {
            if let usage = update.object?["usage"] { return usage }
        }
        return object?["usage"]
    }
}

