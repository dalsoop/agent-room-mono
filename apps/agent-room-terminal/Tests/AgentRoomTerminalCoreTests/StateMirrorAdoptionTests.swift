import XCTest
@testable import AgentRoomTerminalCore

final class StateMirrorAdoptionTests: XCTestCase {
    func testFixturePublisherIncludesNineAppFields() throws {
        let fields = StateMirrorAdoption.fixtureFields()
        let state = StateMirrorAdoption.State(status: "ok", fields: fields)
        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for key in StateMirrorAdoption.appFieldKeys {
            XCTAssertTrue(object.keys.contains(key), "missing \(key)")
        }
        XCTAssertEqual(StateMirrorAdoption.appFieldKeys.count, 9)
        XCTAssertEqual(object["lastDegradeAt"] as? NSNull, NSNull())
        XCTAssertEqual(fields.rooms, RoomListFixture.rooms().filter(\.kind.isLedgerRoom).count)
    }

    func testLastDegradeAtEncodesISO8601() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let state = StateMirrorAdoption.State(
            status: "ok",
            fields: StateMirrorAdoption.Fields(lastDegradeAt: date)
        )
        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let encoded = try XCTUnwrap(object["lastDegradeAt"] as? String)
        XCTAssertEqual(encoded, StateMirrorAdoption.iso8601(date))
        XCTAssertTrue(encoded.contains("2023") || encoded.contains("T"))
    }

    func testHandoffDueCountUsesBudgetState() {
        let due = Budget.compute(
            tool: .grok,
            initialInput: 0,
            used: 320_000,
            elapsedMinutes: 1,
            estimatedWorkMinutes: 60
        )
        let ok = Budget.compute(
            tool: .grok,
            initialInput: 0,
            used: 10,
            elapsedMinutes: 1,
            estimatedWorkMinutes: 60
        )
        let over = Budget.compute(
            tool: .grok,
            initialInput: 0,
            used: 400_000,
            elapsedMinutes: 1,
            estimatedWorkMinutes: 60
        )
        XCTAssertEqual(due.state, .handoffDue)
        XCTAssertEqual(over.state, .over)
        XCTAssertEqual(StateMirrorAdoption.handoffDueCount([due, ok, over, due]), 2)
    }

    func testFixtureHandoffDueMatchesBudgetAggregation() {
        let rooms = RoomListFixture.rooms().filter(\.kind.isLedgerRoom)
        let states = StateMirrorAdoption.budgetStates(from: rooms)
        XCTAssertEqual(
            StateMirrorAdoption.fixtureFields().handoffDue,
            StateMirrorAdoption.handoffDueCount(states)
        )
    }
}
