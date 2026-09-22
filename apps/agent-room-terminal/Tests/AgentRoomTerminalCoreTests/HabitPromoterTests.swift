import XCTest
@testable import AgentRoomTerminalCore

final class HabitPromoterTests: XCTestCase {
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

    func testPromoteBelowThresholdDoesNotPublish() throws {
        let store = HabitStore()
        var habit = try store.create(
            in: room,
            title: "미달 습관",
            steps: [HabitRoomFixture.step(tool: "cli", command: "status")],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        habit.successCount = 4
        habit.failureCount = 0
        try store.save(habit, in: room)
        let wiki = SpyWiki()
        let promoter = HabitPromoter(store: store, wiki: wiki)
        let result = try promoter.promote(room: room, number: habit.number)
        XCTAssertEqual(wiki.argvLog.count, 0)
        XCTAssertNil(result.wikiCandidate)
        XCTAssertNil(result.wikiReceipt)
    }

    func testPromoteWithFailureCountDoesNotPublish() throws {
        let store = HabitStore()
        var habit = try store.create(
            in: room,
            title: "실패 있는 습관",
            steps: [HabitRoomFixture.step(tool: "cli", command: "status")],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        habit.successCount = 5
        habit.failureCount = 1
        try store.save(habit, in: room)
        let wiki = SpyWiki()
        _ = try HabitPromoter(store: store, wiki: wiki).promote(room: room, number: habit.number)
        XCTAssertEqual(wiki.argvLog.count, 0)
    }

    func testPromoteEligibleRunsTwoWikiStepsAndRecordsIDs() throws {
        let store = HabitStore()
        var habit = try store.create(
            in: room,
            title: "안정 습관",
            steps: [HabitRoomFixture.step(tool: "cli", command: "status")],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        habit.successCount = 5
        habit.failureCount = 0
        try store.save(habit, in: room)
        let wiki = SpyWiki(stdoutQueue: ["cand-9f", "rcpt-aa"])
        let result = try HabitPromoter(store: store, wiki: wiki).promote(
            room: room,
            number: habit.number
        )
        XCTAssertEqual(wiki.argvLog.count, 2)
        XCTAssertEqual(
            wiki.argvLog[0],
            ["agent-wiki", "task", "knowledge-candidate", "판매 카탈로그를 운영한다", "안정 습관"]
        )
        XCTAssertEqual(
            wiki.argvLog[1],
            ["agent-wiki", "promotion", "publish", "cand-9f", "--to", "gujo", "--confirm"]
        )
        XCTAssertEqual(wiki.environments.first?["AGENT_WIKI_WORLD"], "tenant-gujo")
        XCTAssertEqual(result.wikiCandidate, "cand-9f")
        XCTAssertEqual(result.wikiReceipt, "rcpt-aa")
        let loaded = try store.load(number: habit.number, in: room)
        XCTAssertEqual(loaded.wikiCandidate, "cand-9f")
        XCTAssertEqual(loaded.wikiReceipt, "rcpt-aa")
    }
}
