import Foundation

/// 단일 전사본 라인에서 토큰 증분과 세션 상태를 추출하는 파서 어댑터.
public struct TranscriptSessionParserAdapter: Sendable {
    public struct ParsedLineResult: Sendable {
        public var totals: UsageTotals
        public var state: TranscriptSessionState?
        public var blockedReason: String?
        public var timestamp: Date?

        public init(
            totals: UsageTotals = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0),
            state: TranscriptSessionState? = nil,
            blockedReason: String? = nil,
            timestamp: Date? = nil
        ) {
            self.totals = totals
            self.state = state
            self.blockedReason = blockedReason
            self.timestamp = timestamp
        }
    }

    public init() {}

    /// 한 줄을 파싱하여 토큰 증분 및 상태를 반환한다.
    public func parseLine(_ line: String, tool: AgentRoomTool?) -> ParsedLineResult {
        guard let data = line.data(using: .utf8) else {
            return ParsedLineResult()
        }
        let json: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ParsedLineResult()
            }
            json = dict
        } catch {
            return ParsedLineResult()
        }

        let date = extractTimestamp(from: json)
        switch tool {
        case .claude:
            return parseClaude(json, date: date)
        case .codex:
            return parseCodex(json, date: date)
        case .grok:
            return parseGrok(json, date: date)
        default:
            return parseGeneric(json, date: date)
        }
    }

    private func extractTimestamp(from dict: [String: Any]) -> Date? {
        if let ts = dict["timestamp"] as? String {
            return ISO8601DateFormatter().date(from: ts)
        }
        if let timeSec = dict["time"] as? Double {
            return Date(timeIntervalSince1970: timeSec)
        }
        return nil
    }

    // MARK: - Claude
    private func parseClaude(_ dict: [String: Any], date: Date?) -> ParsedLineResult {
        let type = (dict["type"] as? String) ?? ""
        var state: TranscriptSessionState?
        var reason: String?

        let message = dict["message"] as? [String: Any]
        let stopReason = (message?["stop_reason"] as? String) ?? (dict["stop_reason"] as? String)
        let isError = (dict["is_error"] as? Bool) ?? (dict["isError"] as? Bool) ?? false

        if type == "error" || stopReason == "error" || isError {
            state = .blocked
            let contentStr = (dict["content"] as? String) ?? (dict["error"] as? String) ?? (dict["message"] as? String)
            reason = contentStr ?? "Claude execution error"
        } else if stopReason == "end_turn" {
            state = .waiting
        } else if type == "human" || type == "user" || type == "assistant" || stopReason == "tool_use" || type == "tool_result" {
            state = .running
        }

        let usage = (message?["usage"] as? [String: Any]) ?? (dict["usage"] as? [String: Any])
        let totals = extractTokens(from: usage)
        return ParsedLineResult(totals: totals, state: state, blockedReason: reason, timestamp: date)
    }

    // MARK: - Codex
    private func parseCodex(_ dict: [String: Any], date: Date?) -> ParsedLineResult {
        let type = (dict["type"] as? String) ?? (dict["event"] as? String) ?? ""
        let payload = dict["payload"] as? [String: Any]
        let payloadType = (payload?["type"] as? String) ?? type
        var state: TranscriptSessionState?
        var reason: String?

        if payloadType.contains("error") || payloadType.contains("failure") {
            state = .blocked
            reason = (dict["error"] as? String) ?? (payload?["error"] as? String) ?? "Codex execution error"
        } else if payloadType.contains("agent_message")
            || payloadType.contains("completed")
            || payloadType.contains("waiting") {
            state = .waiting
        } else if payloadType.contains("user_message")
            || payloadType.contains("started")
            || payloadType.contains("running")
            || payloadType.contains("call") {
            state = .running
        }

        let info = payload?["info"] as? [String: Any]
        let lastUsage = info?["last_token_usage"] as? [String: Any]
        let usage = lastUsage
            ?? (dict["usage"] as? [String: Any])
            ?? (dict["token_usage"] as? [String: Any])
            ?? (payload?["usage"] as? [String: Any])
        let totals = extractTokens(from: usage)
        return ParsedLineResult(totals: totals, state: state, blockedReason: reason, timestamp: date)
    }

    // MARK: - Grok
    private func parseGrok(_ dict: [String: Any], date: Date?) -> ParsedLineResult {
        let params = dict["params"] as? [String: Any]
        let update = (params?["update"] as? [String: Any]) ?? dict
        var state: TranscriptSessionState?
        var reason: String?

        if let stateStr = update["state"] as? String {
            switch stateStr.lowercased() {
            case "blocked":
                state = .blocked
                reason = update["error"] as? String
            case "waiting":
                state = .waiting
            case "running":
                state = .running
            default:
                break
            }
        }

        let usage = (update["usage"] as? [String: Any]) ?? (dict["usage"] as? [String: Any])
        let totals = extractTokens(from: usage)
        return ParsedLineResult(totals: totals, state: state, blockedReason: reason, timestamp: date)
    }

    // MARK: - Generic
    private func parseGeneric(_ dict: [String: Any], date: Date?) -> ParsedLineResult {
        let stateStr = (dict["state"] as? String) ?? (dict["status"] as? String) ?? ""
        var state: TranscriptSessionState?
        var reason: String?

        let lower = stateStr.lowercased()
        if lower.contains("block") || lower.contains("error") {
            state = .blocked
            reason = (dict["error"] as? String) ?? (dict["reason"] as? String)
        } else if lower.contains("wait") || lower.contains("idle") {
            state = .waiting
        } else if lower.contains("run") || lower.contains("exec") {
            state = .running
        }

        let usage = (dict["usage"] as? [String: Any])
        let totals = extractTokens(from: usage ?? dict)
        return ParsedLineResult(totals: totals, state: state, blockedReason: reason, timestamp: date)
    }

    private func extractTokens(from dict: [String: Any]?) -> UsageTotals {
        guard let dict = dict else {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        let input = (dict["input_tokens"] as? Int) ?? (dict["inputTokens"] as? Int) ?? (dict["prompt_tokens"] as? Int) ?? 0
        let output = (dict["output_tokens"] as? Int) ?? (dict["outputTokens"] as? Int) ?? (dict["completion_tokens"] as? Int) ?? 0
        let cache = (dict["cache_read_input_tokens"] as? Int) ??
            (dict["cached_input_tokens"] as? Int) ??
            (dict["cachedReadTokens"] as? Int) ??
            (dict["cached_tokens"] as? Int) ?? 0
        let reqs = (input > 0 || output > 0) ? 1 : 0
        return UsageTotals(inputTokens: input, outputTokens: output, requests: reqs, cacheRead: cache)
    }
}
