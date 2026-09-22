import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("TranscriptLocations — Claude 프로젝트 폴더 슬러그")
struct TranscriptLocationsTests {
    @Test("경로의 / 와 . 이 - 로 바뀐다")
    func slug() {
        let dir = TranscriptLocations.claudeProjectDirectory(
            cwd: "/Users/x/.tenants/gujo/rooms/L1/seller", homeDirectory: "/Users/x"
        )
        #expect(dir == "/Users/x/.claude/projects/-Users-x--tenants-gujo-rooms-L1-seller")
    }

    @Test("claude 와 agy 는 기본 바인딩이 있고 grok 은 아직 없다")
    func defaults() {
        #expect(TranscriptLocations.defaultBinding(tool: .claude, roomPath: "/r", homeDirectory: "/h") != nil)
        let expectedAgy = "/h/.gemini/antigravity-cli/conversation_summaries.db"
        #expect(TranscriptLocations.defaultBinding(tool: .agy, roomPath: "/r", homeDirectory: "/h", environment: [:]) == expectedAgy)
        #expect(TranscriptLocations.defaultBinding(tool: .grok, roomPath: "/r", homeDirectory: "/h") == nil)
    }

    @Test("폴더 바인딩은 안의 jsonl 전부, 없는 폴더는 빈 목록")
    func directoryBinding() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcripts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: dir.appendingPathComponent("b.jsonl"))
        try Data("{}\n".utf8).write(to: dir.appendingPathComponent("a.jsonl"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("note.txt"))
        let files = TranscriptUsageSource.transcriptFiles(for: TranscriptBinding(tool: "claude", path: dir.path))
        #expect(files.map(\.lastPathComponent) == ["a.jsonl", "b.jsonl"])
        let missing = TranscriptUsageSource.transcriptFiles(
            for: TranscriptBinding(tool: "claude", path: dir.path + "/nope")
        )
        #expect(missing.isEmpty)
    }
}

@Test func roomBindingLivesUnderRoomClaudeConfigDir() {
    let binding = TranscriptLocations.defaultBinding(tool: .claude, roomPath: "/r/room", homeDirectory: "/h")
    #expect(binding?.hasPrefix("/r/room/state/claude-config/projects/") == true)
}
