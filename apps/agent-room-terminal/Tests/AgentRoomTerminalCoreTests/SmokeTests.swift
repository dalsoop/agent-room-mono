import XCTest
import AppScaffoldKit
@testable import AgentRoomTerminalCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-room-terminal"))
    }

    func testItemEquatable() {
        XCTAssertEqual(AgentRoomTerminalItem(id: "1", name: "a"), AgentRoomTerminalItem(id: "1", name: "a"))
    }
}
