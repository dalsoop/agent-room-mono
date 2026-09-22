import XCTest
@testable import AgentRoomTerminalCore

final class BudgetComputeTests: XCTestCase {
    /// (a) 4종 계산 픽스처 — initialInput 0, 계수 0.8.
    func testFourToolUsableAndHandoffAtFixtures() {
        let claude = Budget.compute(
            tool: .claude, initialInput: 0, used: 0,
            elapsedMinutes: 0, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(claude.window, 1_000_000)
        XCTAssertEqual(claude.trigger, 0.835)
        XCTAssertEqual(claude.reservedOutput, 0)
        XCTAssertEqual(claude.usable, 835_000)
        XCTAssertEqual(claude.handoffAt, 668_000)
        XCTAssertEqual(claude.state, .ok)

        let codex = Budget.compute(
            tool: .codex, initialInput: 0, used: 0,
            elapsedMinutes: 0, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(codex.window, 272_000)
        XCTAssertEqual(codex.trigger, 1.0)
        XCTAssertEqual(codex.reservedOutput, 0)
        XCTAssertEqual(codex.usable, 259_000)
        XCTAssertEqual(codex.handoffAt, 207_200)

        let grok = Budget.compute(
            tool: .grok, initialInput: 0, used: 0,
            elapsedMinutes: 0, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(grok.window, 500_000)
        XCTAssertEqual(grok.trigger, 0.8)
        XCTAssertEqual(grok.usable, 400_000)
        XCTAssertEqual(grok.handoffAt, 320_000)

        let agy = Budget.compute(
            tool: .agy, initialInput: 0, used: 0,
            elapsedMinutes: 0, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(agy.window, 200_000)
        XCTAssertEqual(agy.trigger, 0.8)
        XCTAssertEqual(agy.usable, 160_000)
        XCTAssertEqual(agy.handoffAt, 128_000)
    }

    func testInitialInputSubtractsFromUsable() {
        let state = Budget.compute(
            tool: .claude, initialInput: 1_000, used: 0,
            elapsedMinutes: 0, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(state.usable, 834_000)
        XCTAssertEqual(state.handoffAt, 667_200)
        XCTAssertEqual(state.initialInput, 1_000)
    }

    /// (b) 토큰 축 handoff-due, 시간 축 handoff-due, 둘 다 미달이면 ok.
    func testHandoffDueOnTokenAxis() {
        let due = Budget.compute(
            tool: .grok, initialInput: 0, used: 320_000,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(due.state, .handoffDue)
        XCTAssertTrue(due.suggestsHandoff)
    }

    func testHandoffDueOnTimeAxis() {
        let due = Budget.compute(
            tool: .grok, initialInput: 0, used: 10,
            elapsedMinutes: 30, estimatedWorkMinutes: 10
        )
        XCTAssertEqual(due.state, .handoffDue)
        XCTAssertTrue(due.suggestsHandoff)
    }

    func testOkWhenTokenAndTimeBelowThreshold() {
        let ok = Budget.compute(
            tool: .grok, initialInput: 0, used: 319_999,
            elapsedMinutes: 29, estimatedWorkMinutes: 10
        )
        XCTAssertEqual(ok.state, .ok)
        XCTAssertFalse(ok.suggestsHandoff)
    }

    func testOverWhenUsedReachesUsable() {
        let over = Budget.compute(
            tool: .agy, initialInput: 0, used: 160_000,
            elapsedMinutes: 0, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(over.state, .over)
        XCTAssertTrue(over.suggestsHandoff)
    }

    /// (c) unknown 이면 제안 없음.
    func testUnknownUsedWithoutTimeIsUnknownAndDoesNotSuggest() {
        let unknown = Budget.compute(
            tool: .claude, initialInput: 0, used: nil,
            elapsedMinutes: nil, estimatedWorkMinutes: nil
        )
        XCTAssertEqual(unknown.state, .unknown)
        XCTAssertFalse(unknown.suggestsHandoff)
    }

    func testUnknownUsedTimeNotDueDoesNotSuggest() {
        let unknown = Budget.compute(
            tool: .claude, initialInput: 0, used: nil,
            elapsedMinutes: 5, estimatedWorkMinutes: 10
        )
        XCTAssertEqual(unknown.state, .unknown)
        XCTAssertFalse(unknown.suggestsHandoff)
    }

    func testUnknownUsedTimeDueIsHandoffDue() {
        let due = Budget.compute(
            tool: .claude, initialInput: 0, used: nil,
            elapsedMinutes: 30, estimatedWorkMinutes: 10
        )
        XCTAssertEqual(due.state, .handoffDue)
        XCTAssertTrue(due.suggestsHandoff)
    }

    /// (e) 도구 교체 시 새 규격으로 재계산.
    func testToolSwitchRecomputesAgainstNewSpec() {
        let claude = Budget.compute(
            tool: .claude, initialInput: 2_000, used: 100,
            elapsedMinutes: 1, estimatedWorkMinutes: 20
        )
        let grok = Budget.compute(
            tool: .grok, initialInput: 2_000, used: 100,
            elapsedMinutes: 1, estimatedWorkMinutes: 20
        )
        XCTAssertEqual(claude.window, 1_000_000)
        XCTAssertEqual(grok.window, 500_000)
        XCTAssertEqual(grok.usable, 398_000)
        XCTAssertEqual(grok.handoffAt, 318_400)
        XCTAssertNotEqual(claude.usable, grok.usable)
        XCTAssertNotEqual(claude.handoffAt, grok.handoffAt)
    }
}
