import Foundation

/// 전사본 증분 소비 커서 항목.
public struct TranscriptCursorEntry: Codable, Equatable, Sendable {
    public var offset: Int64
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int
    public var cacheRead: Int
    public var state: String?
    public var blockedReason: String?
    public var tool: String?

    public init(
        offset: Int64 = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        requests: Int = 0,
        cacheRead: Int = 0,
        state: String? = nil,
        blockedReason: String? = nil,
        tool: String? = nil
    ) {
        self.offset = offset
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
        self.cacheRead = cacheRead
        self.state = state
        self.blockedReason = blockedReason
        self.tool = tool
    }
}

/// 방 `state/usage-cursor.json` 에 저장되는 증분 커서 저장소 어댑터.
public struct TranscriptCursorAdapter: Codable, Equatable, Sendable {
    public var files: [String: TranscriptCursorEntry]

    public init(files: [String: TranscriptCursorEntry] = [:]) {
        self.files = files
    }

    public static func cursorURL(in roomURL: URL) -> URL {
        roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("usage-cursor.json", isDirectory: false)
    }

    public static func load(from url: URL) -> TranscriptCursorAdapter {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TranscriptCursorAdapter()
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TranscriptCursorAdapter.self, from: data)
        } catch {
            return TranscriptCursorAdapter()
        }
    }

    public func save(to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
