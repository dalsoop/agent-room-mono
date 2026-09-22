import Foundation
import AppPathsKit

/// 방 `state/transcripts.json` 한 항목 — CLI 가 세션을 열 때 채운다.
public struct TranscriptBinding: Codable, Equatable, Sendable {
    public var tool: String
    public var path: String
    public var reason: String

    public init(tool: String, path: String, reason: String = TranscriptBindingReason.resolved) {
        self.tool = tool
        self.path = path
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)
        path = try container.decode(String.self, forKey: .path)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
            ?? TranscriptBindingReason.resolved
    }
}

/// 방 폴더에 전사 파일 경로를 등록한다. 목록을 채우는 주체는 CLI.
public enum TranscriptRegistry {
    public static let fileName = "transcripts.json"

    public static func fileURL(in roomURL: URL) -> URL {
        roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func register(roomURL: URL, tool: AgentRoomTool, path: String) throws {
        var bindings = try load(in: roomURL)
        let record = TranscriptBinding(tool: tool.rawValue, path: path, reason: TranscriptBindingReason.resolved)
        if !bindings.contains(where: { $0.tool == record.tool && $0.path == record.path }) {
            bindings.append(record)
        }
        try save(bindings, in: roomURL)
    }

    /// 방에 Gemini(agy) 전사 위치를 등록한다.
    /// workdir 과 매칭되는 conversation 이 있으면 그 db 경로들을 등록하고,
    /// 아직 매칭되는 대화가 없으면 conversation_summaries.db 경로를 기본 등록한다.
    public static func registerAgy(
        roomURL: URL,
        homeDirectory: String = DurableAppLayout.defaultHomeDirectory.path
    ) throws {
        let matches = TranscriptLocations.agyMatchingConversationPaths(
            workdir: roomURL.path,
            homeDirectory: homeDirectory
        )
        if matches.isEmpty {
            if let defaultPath = TranscriptLocations.defaultBinding(
                tool: .agy,
                roomPath: roomURL.path,
                homeDirectory: homeDirectory
            ) {
                try register(roomURL: roomURL, tool: .agy, path: defaultPath)
            }
        } else {
            for path in matches {
                try register(roomURL: roomURL, tool: .agy, path: path)
            }
        }
    }

    public static func load(in roomURL: URL) throws -> [TranscriptBinding] {
        let url = fileURL(in: roomURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [TranscriptBinding] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([TranscriptBinding].self, from: data)
        } catch {
            return try decoder.decode(Envelope.self, from: data).transcripts
        }
    }

    private static func save(_ bindings: [TranscriptBinding], in roomURL: URL) throws {
        let url = fileURL(in: roomURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(bindings)
        try data.write(to: url, options: .atomic)
    }

    private struct Envelope: Codable {
        var transcripts: [TranscriptBinding]
    }
}
