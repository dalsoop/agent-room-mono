import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class BudgetUsageAdapterTests: XCTestCase {
    var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try FileManager.default.removeItem(at: scratch)
        }
        try super.tearDownWithError()
    }

    /// (f) claude transcript JSONL 3줄 합산.
    func testClaudeTranscriptThreeLinesSumsUsage() throws {
        let file = scratch.appendingPathComponent("claude.jsonl")
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hi"}}
        {"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":4,"output_tokens":2}}}
        {"type":"assistant","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":6,"output_tokens":3}}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)
        let reading = ClaudeUsageAdapter().measure(file: file)
        XCTAssertFalse(reading.unknown)
        XCTAssertEqual(reading.inputTokens, 40)
        XCTAssertEqual(reading.outputTokens, 5)
        XCTAssertEqual(reading.requests, 2)
    }

    /// (f) codex 픽스처 합산.
    func testCodexSessionFileSumsUsage() throws {
        let file = scratch.appendingPathComponent("rollout-fixture.jsonl")
        let usage = #""last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":5}"#
        let usage2 = #""last_token_usage":{"input_tokens":200,"cached_input_tokens":20,"output_tokens":7}"#
        let jsonl = """
        {"type":"event_msg","payload":{"type":"token_count","info":{\(usage)}}}
        {"type":"event_msg","payload":{"type":"token_count","info":{\(usage2)}}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)
        let reading = CodexUsageAdapter().measure(file: file)
        XCTAssertFalse(reading.unknown)
        XCTAssertEqual(reading.inputTokens, 330)
        XCTAssertEqual(reading.outputTokens, 12)
        XCTAssertEqual(reading.requests, 2)
    }

    /// (f) grok usage 없음 → unknown.
    func testGrokEnvelopeWithoutUsageIsUnknown() throws {
        let file = scratch.appendingPathComponent("updates.jsonl")
        let jsonl = """
        {"method":"session/update","params":{"update":{"sessionUpdate":"tool_call","title":"Read"}}}
        {"method":"session/update","params":{"update":{"sessionUpdate":"agent_thought_chunk"}}}
        """
        try jsonl.write(to: file, atomically: true, encoding: .utf8)
        let reading = GrokUsageAdapter().measure(file: file)
        XCTAssertTrue(reading.unknown)
        XCTAssertEqual(reading.inputTokens, 0)
        XCTAssertEqual(reading.outputTokens, 0)
    }

    /// (a) 매칭 workdir → requests>0 이고 unknown=false
    func testAgyMatchingWorkdirSumsUsage() throws {
        let summariesFile = try setupAgyFixture()
        let adapter = AgyUsageAdapter(workdir: "/tmp/room-w5-matching")
        let reading = adapter.measure(file: summariesFile)
        XCTAssertFalse(reading.unknown)
        XCTAssertTrue(reading.estimated)
        XCTAssertGreaterThan(reading.requests, 0)
        XCTAssertGreaterThan(reading.inputTokens, 0)
        XCTAssertGreaterThan(reading.outputTokens, 0)
    }

    /// (b) 다른 workdir → 0
    func testAgyDifferentWorkdirReturnsZero() throws {
        let summariesFile = try setupAgyFixture()
        let adapter = AgyUsageAdapter(workdir: "/tmp/unmatched-workdir")
        let reading = adapter.measure(file: summariesFile)
        XCTAssertFalse(reading.unknown)
        XCTAssertEqual(reading.requests, 0)
        XCTAssertEqual(reading.inputTokens, 0)
        XCTAssertEqual(reading.outputTokens, 0)
    }

    /// (c) 파일 부재 → unknown
    func testAgyMissingFileIsUnknown() {
        let missing = scratch.appendingPathComponent("no-such.db")
        let adapter = AgyUsageAdapter(workdir: "/tmp/room-w5-matching")
        let reading = adapter.measure(file: missing)
        XCTAssertTrue(reading.unknown)
        XCTAssertEqual(reading.requests, 0)
    }

    func testMissingFileIsUnknownNotEstimated() {
        let missing = scratch.appendingPathComponent("no-such.jsonl")
        XCTAssertTrue(ClaudeUsageAdapter().measure(file: missing).unknown)
        XCTAssertTrue(CodexUsageAdapter().measure(file: missing).unknown)
        XCTAssertTrue(GrokUsageAdapter().measure(file: missing).unknown)
        XCTAssertTrue(AgyUsageAdapter().measure(file: missing).unknown)
    }

    private func setupAgyFixture() throws -> URL {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/agy", isDirectory: true)
        let target = scratch.appendingPathComponent("gemini-data", isDirectory: true)
        try FileManager.default.copyItem(at: fixtureDir, to: target)
        return target.appendingPathComponent("conversation_summaries.db")
    }

    func testUsageLedgerAppendsAndSums() throws {
        let ledgerFile = scratch.appendingPathComponent("usage.jsonl")
        let ledger = UsageLedger(fileURL: ledgerFile)
        try ledger.append(UsageEntry(
            ts: "2026-09-03T00:00:00Z",
            tool: "claude",
            inputTokens: 10,
            outputTokens: 2,
            requests: 1
        ))
        try ledger.append(UsageEntry(
            ts: "2026-09-03T00:01:00Z",
            tool: "claude",
            inputTokens: 5,
            outputTokens: 1,
            requests: 1
        ))
        let totals = try ledger.totals()
        XCTAssertEqual(totals.inputTokens, 15)
        XCTAssertEqual(totals.outputTokens, 3)
        XCTAssertEqual(totals.requests, 2)
        XCTAssertEqual(totals.used, 18)
    }

    func testCodexSessionsRootUsesStateRootKitHostPath() {
        let root = BudgetHostPaths.codexSessions(
            environment: ["SWIFT_APP_STATE_ROOT": scratch.path],
            homeDirectory: scratch.path
        )
        let expected = scratch.appendingPathComponent(".codex/sessions").path
        XCTAssertEqual(root.path, expected)
    }
}
