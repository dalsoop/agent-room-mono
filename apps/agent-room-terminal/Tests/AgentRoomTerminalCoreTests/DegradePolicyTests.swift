import XCTest
@testable import AgentRoomTerminalCore

final class DegradePolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testExceedLowersCapAndFlagsDegraded() {
        let result = DegradePolicy.next(
            current: DegradePolicy.Current(liveTerminalCap: 8),
            cap: 8,
            p95: 24.1,
            now: now
        )
        XCTAssertEqual(result.cap, 7)
        XCTAssertTrue(result.degraded)
    }

    func testEqualThresholdDoesNotDegrade() {
        let result = DegradePolicy.next(
            current: DegradePolicy.Current(liveTerminalCap: 8),
            cap: 8,
            p95: 24,
            now: now
        )
        XCTAssertEqual(result.cap, 8)
        XCTAssertFalse(result.degraded)
    }

    func testFloorIsOne() {
        let result = DegradePolicy.next(
            current: DegradePolicy.Current(liveTerminalCap: 1),
            cap: 8,
            p95: 80,
            now: now
        )
        XCTAssertEqual(result.cap, 1)
        XCTAssertFalse(result.degraded)
    }

    func testNoRecoverInsideTenSeconds() {
        let result = DegradePolicy.next(
            current: DegradePolicy.Current(
                liveTerminalCap: 6,
                lastDegradeAt: now.addingTimeInterval(-9)
            ),
            cap: 8,
            p95: 10,
            now: now
        )
        XCTAssertEqual(result.cap, 6)
        XCTAssertFalse(result.degraded)
    }

    func testRecoverOneAfterTenSeconds() {
        let result = DegradePolicy.next(
            current: DegradePolicy.Current(
                liveTerminalCap: 6,
                lastDegradeAt: now.addingTimeInterval(-10)
            ),
            cap: 8,
            p95: 10,
            now: now
        )
        XCTAssertEqual(result.cap, 7)
        XCTAssertFalse(result.degraded)
    }

    func testRecoverStopsAtTuningCap() {
        let result = DegradePolicy.next(
            current: DegradePolicy.Current(
                liveTerminalCap: 8,
                lastDegradeAt: now.addingTimeInterval(-30)
            ),
            cap: 8,
            p95: 10,
            now: now
        )
        XCTAssertEqual(result.cap, 8)
        XCTAssertFalse(result.degraded)
    }
}
