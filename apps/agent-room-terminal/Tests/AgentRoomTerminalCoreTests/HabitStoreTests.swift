import XCTest
@testable import AgentRoomTerminalCore

final class HabitStoreTests: XCTestCase {
    var room: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        room = try HabitRoomFixture.makeRoom()
    }

    override func tearDownWithError() throws {
        if let room {
            try FileManager.default.removeItem(at: room)
        }
        try super.tearDownWithError()
    }

    func testIndexTruncatesPastTwentyLines() throws {
        let store = HabitStore()
        for index in 1...22 {
            _ = try store.create(
                in: room,
                title: "절차 \(index)",
                steps: [HabitRoomFixture.step(tool: "cli", command: "status")],
                verify: "true",
                createdBy: HabitTestIDs.handoff
            )
        }
        let text = try String(contentsOf: HabitFile.index(in: room), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 20)
        XCTAssertEqual(String(lines.last ?? ""), "… 외 3건")
        XCTAssertTrue(lines[0].hasPrefix("- 0001 "))
        XCTAssertTrue(lines[18].hasPrefix("- 0019 "))
        XCTAssertFalse(text.contains("0022"))
    }

    func testCandidateAppendWritesOneLine() throws {
        try HabitCandidateStore.append(
            in: room,
            argv: ["ls", "-la"],
            exitCode: 0,
            durationMs: 12,
            tool: "claude",
            clock: ManualDaemonClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let url = HabitFile.candidates(in: room)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("stdout"))
        XCTAssertFalse(text.contains("stderr"))
        let listed = try HabitCandidateStore.list(in: room)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].argv, ["ls", "-la"])
        XCTAssertEqual(listed[0].exitCode, 0)
        XCTAssertEqual(listed[0].durationMs, 12)
        XCTAssertEqual(listed[0].tool, "claude")
        try HabitCandidateStore.append(
            in: room,
            argv: ["false"],
            exitCode: 1,
            durationMs: 3,
            tool: "claude"
        )
        XCTAssertEqual(try HabitCandidateStore.list(in: room).count, 2)
        let promoted = try HabitCandidateStore.promote(in: room, store: HabitStore())
        XCTAssertEqual(promoted.count, 2)
    }

    func testRecordOutcomeUpdatesCountsAndIndex() throws {
        let store = HabitStore(clock: ManualDaemonClock(now: Date(timeIntervalSince1970: 1_700_000_000)))
        let created = try store.create(
            in: room,
            title: "카탈로그 점검",
            steps: [HabitRoomFixture.step(tool: "cli", command: "doctor")],
            verify: "cli doctor",
            createdBy: HabitTestIDs.handoff
        )
        let afterOK = try store.recordOutcome(number: created.number, success: true, in: room)
        XCTAssertEqual(afterOK.successCount, 1)
        XCTAssertEqual(afterOK.failureCount, 0)
        XCTAssertNotNil(afterOK.lastRunAt)
        _ = try store.recordOutcome(number: created.number, success: false, in: room)
        let text = try String(contentsOf: HabitFile.index(in: room), encoding: .utf8)
        XCTAssertEqual(text, "- 0001 카탈로그 점검 (성공 1 / 실패 1)\n")
    }
}
