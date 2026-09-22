import XCTest
@testable import AgentRoomTerminalCore

final class HandoffDigestTests: XCTestCase {
    func testApplyParsesRepeatedFlags() {
        let digest = HandoffDigest.apply(arguments: [
            "handoff", "room-1",
            "--note", "n1",
            "--pitfall", "p1",
            "--decision", "d1",
            "--remaining", "r1",
            "--pitfall", "p2",
            "--decision=d2",
            "--remaining", "r2",
        ])
        XCTAssertEqual(digest.pitfalls, ["p1", "p2"])
        XCTAssertEqual(digest.decisions, ["d1", "d2"])
        XCTAssertEqual(digest.remaining, ["r1", "r2"])
        XCTAssertEqual(HandoffCLIArguments.parse([
            "handoff", "--note", "keep", "--note", "ignore",
        ]).note, "keep")
    }

    func testOldJSONMissingArraysDecodesEmpty() throws {
        let json = """
        {
          "id": "bottle-old",
          "predecessor": null,
          "tool": "claude",
          "budget": {
            "window": 1000000,
            "trigger": 0.835,
            "initialInput": 0,
            "reservedOutput": 0,
            "usable": 835000,
            "handoffAt": 668000,
            "state": "ok"
          }
        }
        """
        let digest = try JSONDecoder().decode(HandoffDigest.self, from: Data(json.utf8))
        XCTAssertEqual(digest.id, "bottle-old")
        XCTAssertEqual(digest.tool, "claude")
        XCTAssertEqual(digest.pitfalls, [])
        XCTAssertEqual(digest.decisions, [])
        XCTAssertEqual(digest.remaining, [])
    }

    func testEscalatedMapsToFailed() {
        XCTAssertEqual(HandoffSimulationLedgerState.fromSimulation("escalated"), "failed")
        XCTAssertEqual(HandoffSimulationLedgerState.fromSimulation("failed"), "failed")
        XCTAssertEqual(HandoffSimulationLedgerState.fromSimulation("passed"), "passed")
        XCTAssertTrue(
            HandoffSimulationLedgerState.escalationNote(handoffID: "b1").contains("escalated")
        )
    }

    func testApplyingMergesOntoExisting() {
        let base = HandoffDigest(
            id: "id",
            predecessor: nil,
            budget: HandoffDigest.emptyBudget,
            tool: "grok",
            pitfalls: ["old"]
        )
        let next = base.applying(arguments: ["--pitfall", "new", "--decision", "d"])
        XCTAssertEqual(next.id, "id")
        XCTAssertEqual(next.tool, "grok")
        XCTAssertEqual(next.pitfalls, ["old", "new"])
        XCTAssertEqual(next.decisions, ["d"])
    }
}
