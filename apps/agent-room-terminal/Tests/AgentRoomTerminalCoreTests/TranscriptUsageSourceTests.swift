import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class TranscriptUsageSourceTests: XCTestCase {
    var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try FileManager.default.removeItem(at: scratch)
        }
        try super.tearDownWithError()
    }

    func testClaudeJSONLThreeMessagesSumsWithoutCacheReadInInput() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("claude.jsonl")
        try claudeFixture(lines: [
            #"{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":1,"output_tokens":2}}}"#,
            #"{"type":"assistant","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":2,"output_tokens":3}}}"#,
            #"{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_read_input_tokens":3,"output_tokens":1}}}"#,
        ]).write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .claude, path: jsonl.path)

        let totals = try TranscriptUsageSource.inRoom(room).totals()
        XCTAssertEqual(totals.inputTokens, 35)
        XCTAssertEqual(totals.outputTokens, 6)
        XCTAssertEqual(totals.requests, 3)
        XCTAssertEqual(totals.cacheRead, 6)
        XCTAssertEqual(totals.used, 41)
    }

    func testIncrementalCursorOnlyReadsNewBytes() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("claude.jsonl")
        try claudeFixture(lines: [
            #"{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":4,"output_tokens":2}}}"#,
            #"{"type":"assistant","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":6,"output_tokens":3}}}"#,
        ]).write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .claude, path: jsonl.path)

        let first = try TranscriptUsageSource.inRoom(room).totals()
        XCTAssertEqual(first.inputTokens, 30)
        XCTAssertEqual(first.outputTokens, 5)
        XCTAssertEqual(first.requests, 2)
        XCTAssertEqual(first.cacheRead, 10)

        let cursorURL = TranscriptUsageSource.cursorURL(in: room)
        let stored = try UsageCursorStore.load(from: cursorURL)
        let offset = try XCTUnwrap(stored.files[jsonl.path]?.offset)
        XCTAssertGreaterThan(offset, 0)

        let handle = try FileHandle(forWritingTo: jsonl)
        try handle.seekToEnd()
        let extra = #"{"type":"assistant","message":{"usage":{"input_tokens":7,"cache_read_input_tokens":1,"output_tokens":4}}}"# + "\n"
        try handle.write(contentsOf: Data(extra.utf8))
        try handle.close()

        let second = try TranscriptUsageSource.inRoom(room).totals()
        XCTAssertEqual(second.inputTokens, 37)
        XCTAssertEqual(second.outputTokens, 9)
        XCTAssertEqual(second.requests, 3)
        XCTAssertEqual(second.cacheRead, 11)

        let after = try UsageCursorStore.load(from: cursorURL)
        XCTAssertGreaterThan(try XCTUnwrap(after.files[jsonl.path]?.offset), offset)
    }

    func testBrokenJSONLineThrows() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("claude.jsonl")
        try claudeFixture(lines: [
            #"{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":0,"output_tokens":1}}}"#,
            "{not-json",
        ]).write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .claude, path: jsonl.path)

        XCTAssertThrowsError(try TranscriptUsageSource.inRoom(room).totals()) { error in
            guard case TranscriptUsageError.invalidJSON = error else {
                XCTFail("expected invalidJSON, got \(error)")
                return
            }
        }
    }

    func testRoomWithTranscriptsBudgetStateIsNotUnknown() throws {
        let room = try makeRoom()
        let jsonl = scratch.appendingPathComponent("claude.jsonl")
        try claudeFixture(lines: [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":4,"output_tokens":2}}}"#,
            #"{"type":"assistant","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":6,"output_tokens":3}}}"#,
        ]).write(to: jsonl, atomically: true, encoding: .utf8)
        try TranscriptRegistry.register(roomURL: room, tool: .claude, path: jsonl.path)

        let totals = try UsageLedger.inRoom(room).totals()
        XCTAssertEqual(totals.inputTokens, 30)
        XCTAssertEqual(totals.cacheRead, 10)
        let budget = Budget.compute(
            tool: .claude,
            initialInput: 0,
            used: totals.used,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
        XCTAssertNotEqual(budget.state, .unknown)
        XCTAssertEqual(budget.state, .ok)
        XCTAssertEqual(budget.used, 35)
    }

    func testRoomWithAgyTranscriptTotalsAndBudget() throws {
        let room = URL(fileURLWithPath: "/tmp/room-w5-matching")
        try FileManager.default.createDirectory(
            at: room.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: room.appendingPathComponent("state"))
        }

        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/agy", isDirectory: true)
        let summariesFile = fixtureDir.appendingPathComponent("conversation_summaries.db")

        try TranscriptRegistry.register(roomURL: room, tool: .agy, path: summariesFile.path)

        let totals = try TranscriptUsageSource.inRoom(room).totals()
        XCTAssertGreaterThan(totals.requests, 0)
        XCTAssertGreaterThan(totals.used, 0)
        XCTAssertTrue(totals.estimated)

        let budget = Budget.compute(
            tool: .agy,
            initialInput: 0,
            used: totals.used,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
        XCTAssertNotEqual(budget.state, .unknown)
        XCTAssertEqual(budget.state, .ok)
    }

    private func makeRoom() throws -> URL {
        let room = scratch.appendingPathComponent("room", isDirectory: true)
        try FileManager.default.createDirectory(
            at: room.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        return room
    }

    private func claudeFixture(lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}
