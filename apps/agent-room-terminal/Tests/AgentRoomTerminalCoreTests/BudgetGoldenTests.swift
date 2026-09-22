import XCTest
import RoomKit
@testable import AgentRoomTerminalCore

/// 예산 정본 RoomKit 이전(2026-09-07) 동작 동일 증명.
/// 1) 옛 JSON Decodable 호환 — room-terminal 구현의 인코딩 레이아웃을 그대로 디코딩한다.
/// 2) 같은 입력 → 같은 BudgetPhase — 얇은 접착 Budget.compute 와 RoomKit BudgetJudgment 일치.
final class BudgetGoldenTests: XCTestCase {
    /// 국면 판정 표의 한 행.
    private struct PhaseCase {
        let tool: AgentRoomTool
        let used: Int?
        let elapsed: Int?
        let estimated: Int?
        let expected: BudgetPhase
    }

    /// 옛 room-terminal BudgetState 의 JSON 인코딩 결과(raw 값 보존).
    private static let legacyJSON = """
    {"window":1000000,"trigger":0.835,"initialInput":0,"reservedOutput":0,\
    "usable":835000,"used":668000,"handoffAt":668000,"elapsedMinutes":null,\
    "estimatedWorkMinutes":null,"state":"handoff-due"}
    """

    func testLegacyJSONDecodesWithSameFieldsAndPhase() throws {
        let state = try JSONDecoder().decode(BudgetState.self, from: Data(Self.legacyJSON.utf8))
        XCTAssertEqual(state.window, 1_000_000)
        XCTAssertEqual(state.trigger, 0.835)
        XCTAssertEqual(state.initialInput, 0)
        XCTAssertEqual(state.reservedOutput, 0)
        XCTAssertEqual(state.usable, 835_000)
        XCTAssertEqual(state.used, 668_000)
        XCTAssertEqual(state.handoffAt, 668_000)
        XCTAssertNil(state.elapsedMinutes)
        XCTAssertNil(state.estimatedWorkMinutes)
        XCTAssertEqual(state.state, .handoffDue)
        XCTAssertTrue(state.suggestsHandoff)
        XCTAssertEqual(state.remainder, 167_000)
    }

    /// 옛 구현은 Optional 키가 JSON 에 빠져도 디코딩됐다 — 합성 Codable 이 decodeIfPresent 를 쓰기 때문.
    func testLegacyJSONWithAbsentOptionalKeysDecodes() throws {
        let json = """
        {"window":272000,"trigger":1.0,"initialInput":0,"reservedOutput":0,\
        "usable":259000,"handoffAt":207200,"state":"ok"}
        """
        let state = try JSONDecoder().decode(BudgetState.self, from: Data(json.utf8))
        XCTAssertEqual(state.state, .ok)
        XCTAssertNil(state.used)
        XCTAssertEqual(state.remainder, 259_000)
        XCTAssertFalse(state.suggestsHandoff)
    }

    /// 다시 인코딩한 JSON 은 같은 값으로 디코딩된다 — 소비자(핸드오프 JSON) 왕등 호환 유지.
    func testEncodeRoundTripPreservesState() throws {
        let state = try JSONDecoder().decode(BudgetState.self, from: Data(Self.legacyJSON.utf8))
        let data = try JSONEncoder().encode(state)
        let reparsed = try JSONDecoder().decode(BudgetState.self, from: data)
        XCTAssertEqual(reparsed, state)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(encoded.contains("\"state\":\"handoff-due\""))
        XCTAssertTrue(encoded.contains("\"used\":668000"))
    }

    /// 같은 입력이면 접착 계산과 정본 판정이 같은 BudgetPhase 를 낸다 — 전 국면 표.
    func testSameInputYieldsSamePhaseAcrossAllBranches() {
        let cases = [
            PhaseCase(tool: .grok, used: 0, elapsed: 0, estimated: 60, expected: .ok),
            PhaseCase(tool: .grok, used: 319_999, elapsed: 29, estimated: 10, expected: .ok),
            PhaseCase(tool: .grok, used: 320_000, elapsed: 1, estimated: 60, expected: .handoffDue),
            PhaseCase(tool: .grok, used: 10, elapsed: 30, estimated: 10, expected: .handoffDue),
            PhaseCase(tool: .agy, used: 160_000, elapsed: 0, estimated: 60, expected: .over),
            PhaseCase(tool: .claude, used: nil, elapsed: nil, estimated: nil, expected: .unknown),
            PhaseCase(tool: .claude, used: nil, elapsed: 5, estimated: 10, expected: .unknown),
            PhaseCase(tool: .claude, used: nil, elapsed: 30, estimated: 10, expected: .handoffDue),
        ]
        for phaseCase in cases {
            let computed = Budget.compute(
                tool: phaseCase.tool,
                initialInput: 0,
                used: phaseCase.used,
                elapsedMinutes: phaseCase.elapsed,
                estimatedWorkMinutes: phaseCase.estimated
            )
            let judged = BudgetJudgment.phase(
                used: phaseCase.used,
                usable: computed.usable,
                handoffAt: computed.handoffAt,
                elapsedMinutes: phaseCase.elapsed,
                estimatedWorkMinutes: phaseCase.estimated
            )
            let where_ = "used=\(String(describing: phaseCase.used)) elapsed=\(String(describing: phaseCase.elapsed))"
            XCTAssertEqual(computed.state, phaseCase.expected, where_)
            XCTAssertEqual(judged, phaseCase.expected, where_)
        }
    }
}
