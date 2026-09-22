import Foundation
import AgentSessionKit

/// span 클릭 → 원문 (C.15). TranscriptReader 만 쓴다.
public struct TranscriptLookup: Sendable {
    public init() {}

    public struct Excerpt: Sendable, Equatable {
        public var role: String
        public var text: String
        public var at: Date?
        public init(role: String, text: String, at: Date? = nil) {
            self.role = role
            self.text = text
            self.at = at
        }
    }

    /// `sourcePath` 가 파일이면 그 경로, 디렉터리면 grok updates.jsonl.
    public func excerpts(sourcePath: String, around unix: Double?, limit: Int = 8) -> [Excerpt] {
        let url = URL(fileURLWithPath: sourcePath)
        let isDir: Bool
        do {
            isDir = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        } catch {
            isDir = false
        }
        let tool = Self.guessTool(path: sourcePath)
        let ref = SessionRef(
            tool: tool,
            id: url.deletingPathExtension().lastPathComponent,
            cwd: url.deletingLastPathComponent().path,
            title: nil,
            lastActive: Date(),
            path: isDir ? sourcePath : sourcePath,
            messageCount: 0
        )
        let turns = TranscriptReader.read(ref, maxBytes: 512 * 1024, fromTail: true).turns
        let target = unix.map { Date(timeIntervalSince1970: $0) }
        let picked: [TranscriptReader.Turn]
        if let target {
            picked = Array(turns.sorted {
                abs(($0.at ?? .distantPast).timeIntervalSince(target))
                    < abs(($1.at ?? .distantPast).timeIntervalSince(target))
            }.prefix(limit))
        } else {
            picked = Array(turns.suffix(limit))
        }
        return picked.map {
            Excerpt(role: $0.role.rawValue, text: String($0.text.prefix(800)), at: $0.at)
        }
    }

    static func guessTool(path: String) -> AgentTool {
        if path.contains("/.codex/") { return .codex }
        if path.contains("grok") { return .grok }
        return .claude
    }
}
