import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class TranscriptBudgetAdapterTests: XCTestCase {
    var scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    private func makeRoom() throws -> URL {
        let room = scratch.appendingPathComponent("room", isDirectory: true)
        try FileManager.default.createDirectory(
            at: room.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        return room
    }

    // MARK: - 1. 빈 방 검증
    func testEmptyRoomReturnsUnknown() throws {
        let room = try makeRoom()
        let adapter = TranscriptBudgetAdapter.inRoom(room)
        let report = try adapter.report()

        XCTAssertTrue(report.isUnknown)
        XCTAssertEqual(report.used, 0)
        XCTAssertEqual(report.state, .unknown)
        XCTAssertNil(report.blockedReason)
    }

    // MARK: - 2. Claude 전사본 상태 전이 및 토큰 산출
    func testClaudeTranscriptStateTransitionsAndTokens() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("claude.jsonl")

        // 1) User message -> running
        let lines1 = [
            #"{"type":"user","message":{"role":"user","content":"build the app"}}"#
        ]
        try lines1.joined(separator: "\n").appending("\n").write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .claude, path: jsonl.path)

        let adapter = TranscriptBudgetAdapter.inRoom(room)
        var report = try adapter.report()
        XCTAssertEqual(report.state, .running)

        // 2) Assistant tool use -> running + tokens
        let msg2 = #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","#
            + #""content":[{"type":"tool_use","name":"bash","input":{"command":"swift build"}}],"#
            + #""usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":10}}}"#
        let lines2 = [msg2]
        let handle = try FileHandle(forWritingTo: jsonl)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines2.joined(separator: "\n").appending("\n").utf8))
        try handle.close()

        report = try adapter.report()
        XCTAssertEqual(report.state, .running)
        XCTAssertEqual(report.inputTokens, 100)
        XCTAssertEqual(report.outputTokens, 20)
        XCTAssertEqual(report.used, 120)
        XCTAssertEqual(report.cacheRead, 10)

        // 3) Assistant end_turn -> waiting
        let msg3 = #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","#
            + #""content":[{"type":"text","text":"Build succeeded."}],"#
            + #""usage":{"input_tokens":50,"output_tokens":15,"cache_read_input_tokens":5}}}"#
        let lines3 = [msg3]
        let handle2 = try FileHandle(forWritingTo: jsonl)
        try handle2.seekToEnd()
        try handle2.write(contentsOf: Data(lines3.joined(separator: "\n").appending("\n").utf8))
        try handle2.close()

        report = try adapter.report()
        XCTAssertEqual(report.state, .waiting)
        XCTAssertEqual(report.inputTokens, 150)
        XCTAssertEqual(report.outputTokens, 35)
        XCTAssertEqual(report.used, 185)

        // 4) Tool result with blocked execution -> blocked
        let lines4 = [
            #"{"type":"tool_result","is_error":true,"content":"tool Agent is blocked inside a room"}"#
        ]
        let handle3 = try FileHandle(forWritingTo: jsonl)
        try handle3.seekToEnd()
        try handle3.write(contentsOf: Data(lines4.joined(separator: "\n").appending("\n").utf8))
        try handle3.close()

        report = try adapter.report()
        XCTAssertEqual(report.state, .blocked)
        XCTAssertNotNil(report.blockedReason)
        XCTAssertEqual(report.blockedReason?.contains("blocked"), true)
    }

    // MARK: - 3. Codex 전사본 상태 및 토큰 산출
    func testCodexTranscriptStates() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("codex.jsonl")

        let msg3 = #"{"type":"agent_message","payload":{"type":"agent_message","message":"done","#
            + #""info":{"last_token_usage":{"input_tokens":200,"output_tokens":50,"cached_input_tokens":20}}}}"#
        let lines = [
            #"{"type":"session_meta","payload":{"type":"session_meta","id":"sess-1","cwd":"/work"}}"#,
            #"{"type":"user_message","payload":{"type":"user_message","message":"run test"}}"#,
            msg3
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .codex, path: jsonl.path)

        let adapter = TranscriptBudgetAdapter.inRoom(room)
        let report = try adapter.report()
        XCTAssertEqual(report.state, .waiting)
        XCTAssertEqual(report.inputTokens, 200)
        XCTAssertEqual(report.outputTokens, 50)
        XCTAssertEqual(report.used, 250)
        XCTAssertEqual(report.cacheRead, 20)
    }

    // MARK: - 4. Grok 전사본 상태 및 토큰 산출
    func testGrokTranscriptStates() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("updates.jsonl")

        let lines = [
            #"{"params":{"update":{"state":"running","usage":{"inputTokens":300,"outputTokens":80,"cachedReadTokens":30}}}}"#,
            #"{"params":{"update":{"state":"blocked","error":"sandbox violation"}}}"#
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .grok, path: jsonl.path)

        let adapter = TranscriptBudgetAdapter.inRoom(room)
        let report = try adapter.report()
        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.inputTokens, 300)
        XCTAssertEqual(report.outputTokens, 80)
        XCTAssertEqual(report.used, 380)
    }

    // MARK: - 5. 방 state/ 디렉터리 내 미등록 세션 로그 자동 탐색
    func testAutoDiscoversSessionLogInRoomStateDir() throws {
        let room = try makeRoom()
        let stateDir = room.appendingPathComponent("state", isDirectory: true)
        let logFile = stateDir.appendingPathComponent("claude-session.jsonl")

        let msg2 = #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","#
            + #""content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":40,"output_tokens":10}}}"#
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hello"}}"#,
            msg2
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: logFile, atomically: true, encoding: .utf8)

        // transcripts.json 에는 등록하지 않음!
        let adapter = TranscriptBudgetAdapter.inRoom(room)
        let report = try adapter.report()

        XCTAssertFalse(report.isUnknown)
        XCTAssertEqual(report.state, .waiting)
        XCTAssertEqual(report.used, 50)
        XCTAssertEqual(report.requests, 1)
    }

    // MARK: - 6. 증분 tail 커서 보존 및 멱등성 검증
    func testIncrementalCursorPreservesTokensAndState() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("claude.jsonl")

        let msg1 = #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","#
            + #""content":[{"type":"tool_use","name":"sh"}],"usage":{"input_tokens":10,"output_tokens":5}}}"#
        let lines1 = [
            #"{"type":"user","message":{"role":"user","content":"step 1"}}"#,
            msg1
        ]
        try lines1.joined(separator: "\n").appending("\n").write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .claude, path: jsonl.path)

        let adapter = TranscriptBudgetAdapter.inRoom(room)
        let report1 = try adapter.report()
        XCTAssertEqual(report1.state, .running)
        XCTAssertEqual(report1.used, 15)

        // 파일 변경 없이 다시 호출해도 동일한 결과 반환 (커서 캐시)
        let report2 = try adapter.report()
        XCTAssertEqual(report2.state, .running)
        XCTAssertEqual(report2.used, 15)

        // 새 줄 추가 후 호출 시 증분 합산 및 상태 갱신
        let msg2 = #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","#
            + #""content":[{"type":"text","text":"done"}],"usage":{"input_tokens":20,"output_tokens":10}}}"#
        let lines2 = [msg2]
        let handle = try FileHandle(forWritingTo: jsonl)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines2.joined(separator: "\n").appending("\n").utf8))
        try handle.close()

        let report3 = try adapter.report()
        XCTAssertEqual(report3.state, .waiting)
        XCTAssertEqual(report3.used, 45)
        XCTAssertEqual(report3.inputTokens, 30)
        XCTAssertEqual(report3.outputTokens, 15)
    }
}
