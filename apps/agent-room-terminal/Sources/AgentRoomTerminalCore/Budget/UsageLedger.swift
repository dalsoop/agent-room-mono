import Foundation

/// 방 `state/usage.jsonl` 한 줄.
public struct UsageEntry: Codable, Equatable, Sendable {
    public var ts: String
    public var tool: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int

    public init(
        ts: String,
        tool: String,
        inputTokens: Int,
        outputTokens: Int,
        requests: Int
    ) {
        self.ts = ts
        self.tool = tool
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
    }
}

public struct UsageTotals: Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int
    public var cacheRead: Int
    public var estimated: Bool

    public var used: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int, requests: Int, cacheRead: Int = 0, estimated: Bool = false) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
        self.cacheRead = cacheRead
        self.estimated = estimated
    }
}

/// 방 사용량 원장. 추정치를 쓰지 않고 측정된 줄만 누적한다.
/// 합산 우선순위: 전사(`state/transcripts.json`) → `usage.jsonl` → 빈 totals(unknown).
public struct UsageLedger: Sendable {
    public var fileURL: URL
    public var roomURL: URL?

    public init(fileURL: URL, roomURL: URL? = nil) {
        self.fileURL = fileURL
        self.roomURL = roomURL
    }

    public static func inRoom(_ roomURL: URL) -> UsageLedger {
        let url = roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("usage.jsonl", isDirectory: false)
        return UsageLedger(fileURL: url, roomURL: roomURL)
    }

    public func append(_ entry: UsageEntry) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(entry)
        line.append(contentsOf: "\n".utf8)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }

    public func append(reading: UsageReading, ts: String) throws {
        if reading.unknown { return }
        try append(UsageEntry(
            ts: ts,
            tool: reading.tool.rawValue,
            inputTokens: reading.inputTokens,
            outputTokens: reading.outputTokens,
            requests: reading.requests
        ))
    }

    /// 전사 delta 와 `usage.jsonl` 줄을 **합산**한다. 코드 안에서 `usage.jsonl` 에 줄을 쓰는
    /// 곳은 없고(외부 도구·수동 기록 전용) 전사 커서는 따로 저장되므로 이중 계수가 없다.
    /// 전사 바인딩이 있다고 `usage.jsonl` 을 버리면 수동 기록이 사라진다(스모크 테스트가 잡음).
    public func totals() throws -> UsageTotals {
        var sum = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        if let roomURL {
            let bindings = try TranscriptRegistry.load(in: roomURL)
            if !bindings.isEmpty {
                sum = sum.adding(try TranscriptUsageSource.inRoom(roomURL).totals())
            }
        }
        for entry in try load() {
            sum = sum.adding(UsageTotals(
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                requests: entry.requests
            ))
        }
        return sum
    }

    public func load() throws -> [UsageEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [UsageEntry] = []
        let decoder = JSONDecoder()
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            entries.append(try decoder.decode(UsageEntry.self, from: data))
        }
        return entries
    }
}
