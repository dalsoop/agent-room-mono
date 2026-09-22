import Foundation

public enum TranscriptUsageError: Error, LocalizedError, Equatable {
    case invalidJSON(path: String, line: String)
    case unreadable(path: String, message: String)
    case invalidEncoding(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let path, let line):
            return "invalid JSON in \(path): \(line)"
        case .unreadable(let path, let message):
            return "unreadable transcript \(path): \(message)"
        case .invalidEncoding(let path):
            return "transcript is not UTF-8: \(path)"
        }
    }
}

/// 방 `state/transcripts.json` 이 가리키는 JSONL 을 tail 해 `UsageTotals` 를 낸다.
public struct TranscriptUsageSource: Sendable {
    public var roomURL: URL

    public init(roomURL: URL) {
        self.roomURL = roomURL
    }

    public static func inRoom(_ roomURL: URL) -> TranscriptUsageSource {
        TranscriptUsageSource(roomURL: roomURL)
    }

    public static func cursorURL(in roomURL: URL) -> URL {
        roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("usage-cursor.json", isDirectory: false)
    }

    public func totals() throws -> UsageTotals {
        let bindings = try TranscriptRegistry.load(in: roomURL)
        if bindings.isEmpty {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        var store = try UsageCursorStore.load(from: Self.cursorURL(in: roomURL))
        var sum = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        for binding in bindings {
            if binding.tool == AgentRoomTool.agy.rawValue {
                let adapter = AgyUsageAdapter(workdir: roomURL.path)
                let reading = adapter.measure(file: URL(fileURLWithPath: binding.path))
                if !reading.unknown {
                    sum = sum.adding(UsageTotals(
                        inputTokens: reading.inputTokens,
                        outputTokens: reading.outputTokens,
                        requests: reading.requests,
                        estimated: reading.estimated
                    ))
                }
            } else {
                for fileURL in Self.transcriptFiles(for: binding) {
                    let delta = try consume(binding: binding, fileURL: fileURL, store: &store)
                    sum = sum.adding(delta)
                }
            }
        }
        try store.save(to: Self.cursorURL(in: roomURL))
        return sum
    }

    private func consume(
        binding: TranscriptBinding,
        fileURL: URL,
        store: inout UsageCursorStore
    ) throws -> UsageTotals {
        let key = fileURL.path
        let size = try fileSize(fileURL)
        var entry = store.files[key] ?? UsageCursorEntry()
        if entry.offset > size {
            entry = UsageCursorEntry()
        }
        let chunk = try readCompleteLines(from: fileURL, offset: entry.offset)
        let tool = AgentRoomTool(rawValue: binding.tool)
        var delta = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        for line in chunk.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parsed = try parseLine(trimmed, tool: tool, path: key)
            delta = delta.adding(parsed)
        }
        entry.offset = chunk.newOffset
        entry.inputTokens += delta.inputTokens
        entry.outputTokens += delta.outputTokens
        entry.requests += delta.requests
        entry.cacheRead += delta.cacheRead
        store.files[key] = entry
        return UsageTotals(
            inputTokens: entry.inputTokens,
            outputTokens: entry.outputTokens,
            requests: entry.requests,
            cacheRead: entry.cacheRead
        )
    }

    /// 바인딩 경로가 폴더(예 Claude 의 프로젝트 폴더)면 그 안의 `*.jsonl` 전부, 파일이면 그 하나.
    /// 아직 없는 폴더는 빈 목록 — 세션이 첫 메시지를 쓰기 전이 정상이다.
    static func transcriptFiles(for binding: TranscriptBinding) -> [URL] {
        let url = URL(fileURLWithPath: binding.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else { return [url] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        } catch {
            return []
        }
        return names.filter { $0.hasSuffix(".jsonl") }.sorted().map { url.appendingPathComponent($0) }
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            throw TranscriptUsageError.unreadable(path: url.path, message: error.localizedDescription)
        }
    }

    private func readCompleteLines(from url: URL, offset: Int64) throws -> (lines: [String], newOffset: Int64) {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw TranscriptUsageError.unreadable(path: url.path, message: error.localizedDescription)
        }
        let data: Data
        do {
            try handle.seek(toOffset: UInt64(max(0, offset)))
            data = try handle.readToEnd() ?? Data()
            try handle.close()
        } catch {
            throw TranscriptUsageError.unreadable(path: url.path, message: error.localizedDescription)
        }
        var lines: [String] = []
        var consumed = 0
        var start = 0
        let newline = UInt8(ascii: "\n")
        for index in data.indices {
            if data[index] == newline {
                let slice = data[start..<index]
                guard let text = String(data: Data(slice), encoding: .utf8) else {
                    throw TranscriptUsageError.invalidEncoding(path: url.path)
                }
                lines.append(text)
                consumed = index + 1
                start = index + 1
            }
        }
        return (lines, offset + Int64(consumed))
    }

    private func parseLine(_ line: String, tool: AgentRoomTool?, path: String) throws -> UsageTotals {
        let data = Data(line.utf8)
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw TranscriptUsageError.invalidJSON(path: path, line: line)
        }
        switch tool {
        case .claude:
            return claudeTotals(in: value)
        case .codex:
            return codexTotals(in: value)
        case .grok:
            return grokTotals(in: value)
        case .agy, nil:
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
    }

    /// Claude Code JSONL: `message.usage.{input_tokens,output_tokens,cache_read_input_tokens}`.
    /// `cache_read` 는 input 에 넣지 않는다.
    private func claudeTotals(in line: JSONValue) -> UsageTotals {
        guard let usage = claudeUsage(in: line) else {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        let input = int(usage, keys: ["input_tokens"])
        let output = int(usage, keys: ["output_tokens"])
        let cacheRead = int(usage, keys: ["cache_read_input_tokens"])
        return UsageTotals(
            inputTokens: input,
            outputTokens: output,
            requests: 1,
            cacheRead: cacheRead
        )
    }

    private func claudeUsage(in line: JSONValue) -> JSONValue? {
        guard let object = line.object else { return nil }
        let message = object["message"]
        let type = object["type"]?.string
        let role = message?.object?["role"]?.string
        let isAssistant = type == "assistant" || role == "assistant"
        if !isAssistant { return nil }
        return message?.object?["usage"] ?? object["usage"]
    }

    /// Codex JSONL 실측(2026-09-03): `payload.info.last_token_usage` /
    /// `payload.info.total_token_usage` 에 `input_tokens`, `output_tokens`,
    /// `cached_input_tokens`. 턴 합산은 `last_token_usage` 만. 없으면 이 줄은 0.
    private func codexTotals(in line: JSONValue) -> UsageTotals {
        guard let usage = codexUsage(in: line) else {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        let input = int(usage, keys: ["input_tokens", "inputTokens"])
        let output = int(usage, keys: ["output_tokens", "outputTokens"])
        let cacheRead = int(usage, keys: ["cached_input_tokens", "cachedInputTokens"])
        if input == 0 && output == 0 && cacheRead == 0 {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        return UsageTotals(
            inputTokens: input,
            outputTokens: output,
            requests: 1,
            cacheRead: cacheRead
        )
    }

    private func codexUsage(in line: JSONValue) -> JSONValue? {
        if let direct = line.object?["usage"] { return direct }
        guard let payload = line.object?["payload"]?.object else { return nil }
        if let usage = payload["usage"] { return usage }
        let info = payload["info"]?.object
        if let last = info?["last_token_usage"] ?? info?["lastTokenUsage"] {
            return last
        }
        return nil
    }

    /// Grok `~/.grok/sessions/.../updates.jsonl` 실측: usage 필드가 없으면 0
    /// (unknown 과 동일 — 추정하지 않음).
    private func grokTotals(in line: JSONValue) -> UsageTotals {
        guard let usage = grokUsage(in: line) else {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        let input = int(usage, keys: ["inputTokens", "input_tokens"])
        let output = int(usage, keys: ["outputTokens", "output_tokens"])
        let cacheRead = int(usage, keys: ["cachedReadTokens", "cache_read_input_tokens"])
        if input == 0 && output == 0 && cacheRead == 0 {
            return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        }
        return UsageTotals(
            inputTokens: input,
            outputTokens: output,
            requests: 1,
            cacheRead: cacheRead
        )
    }

    private func grokUsage(in line: JSONValue) -> JSONValue? {
        let object = line.object
        if let update = object?["params"]?.object?["update"] {
            if let usage = update.object?["usage"] { return usage }
        }
        return object?["usage"]
    }

    private func int(_ value: JSONValue?, keys: [String]) -> Int {
        guard let object = value?.object else { return 0 }
        for key in keys {
            if let number = object[key]?.int { return number }
        }
        return 0
    }
}

struct UsageCursorEntry: Codable, Equatable, Sendable {
    var offset: Int64
    var inputTokens: Int
    var outputTokens: Int
    var requests: Int
    var cacheRead: Int

    init(
        offset: Int64 = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        requests: Int = 0,
        cacheRead: Int = 0
    ) {
        self.offset = offset
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
        self.cacheRead = cacheRead
    }
}

struct UsageCursorStore: Codable, Equatable, Sendable {
    var files: [String: UsageCursorEntry]

    init(files: [String: UsageCursorEntry] = [:]) {
        self.files = files
    }

    static func load(from url: URL) throws -> UsageCursorStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return UsageCursorStore()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UsageCursorStore.self, from: data)
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

extension UsageTotals {
    func adding(_ other: UsageTotals) -> UsageTotals {
        UsageTotals(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            requests: requests + other.requests,
            cacheRead: cacheRead + other.cacheRead,
            estimated: estimated || other.estimated
        )
    }
}
