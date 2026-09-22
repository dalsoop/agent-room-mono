import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomToolDetector — 방 도구 감지 및 자격 검사 판정")
struct RoomToolDetectorTests {
    @Test("occupant 핸들에서 도구를 파싱한다")
    func parsesToolFromHandle() {
        #expect(RoomToolDetector.parseToolFromHandle("agent:claude@macbook") == .claude)
        #expect(RoomToolDetector.parseToolFromHandle("agent:agy@macbook") == .agy)
        #expect(RoomToolDetector.parseToolFromHandle("agent:antigravity@macbook") == .agy)
        #expect(RoomToolDetector.parseToolFromHandle("agent:antigravity") == .agy)
        #expect(RoomToolDetector.parseToolFromHandle("agy") == .agy)
        #expect(RoomToolDetector.parseToolFromHandle("antigravity") == .agy)
        #expect(RoomToolDetector.parseToolFromHandle("claude") == .claude)
        #expect(RoomToolDetector.parseToolFromHandle("agent:codex@host") == .codex)
        #expect(RoomToolDetector.parseToolFromHandle("codex") == .codex)
        #expect(RoomToolDetector.parseToolFromHandle("agent:grok@host") == .grok)
        #expect(RoomToolDetector.parseToolFromHandle("grok") == .grok)
        #expect(RoomToolDetector.parseToolFromHandle("unknown-handle") == nil)
        #expect(RoomToolDetector.parseToolFromHandle("agent:unknown@host") == nil)
    }

    @Test("claude 만 credential check 가 필요하다")
    func onlyClaudeNeedsCredentialCheck() {
        #expect(RoomToolDetector.needsCredentialCheck(tool: .claude))
        #expect(!RoomToolDetector.needsCredentialCheck(tool: .agy))
        #expect(!RoomToolDetector.needsCredentialCheck(tool: .codex))
        #expect(!RoomToolDetector.needsCredentialCheck(tool: .grok))
    }

    @Test("agy 방은 Claude 자격 검사를 하지 않는다")
    func agyRoomSkipsClaudeCheck() {
        let occupants = [RoomOccupant(handle: "agent:agy@macbook", isSuccessor: false)]
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-detect-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        } catch {
            Issue.record("디렉터리 생성 실패: \(error)")
            return
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        let tool = RoomToolDetector.detect(roomURL: temp, occupants: occupants)
        #expect(tool == .agy)
        #expect(!RoomToolDetector.needsCredentialCheck(tool: tool))
    }

    @Test("occupant 없이 spec.json 의 launch.tool 로 감지한다")
    func detectsFromSpec() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-spec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let spec = RoomSpec(
            tenant: "tenant:test",
            task: "test",
            verdict: "true",
            launch: RoomLaunch(tool: .grok)
        )
        let data = try JSONEncoder().encode(spec)
        try data.write(to: temp.appendingPathComponent("spec.json"))

        let tool = RoomToolDetector.detect(roomURL: temp, occupants: [])
        #expect(tool == .grok)
    }
}
