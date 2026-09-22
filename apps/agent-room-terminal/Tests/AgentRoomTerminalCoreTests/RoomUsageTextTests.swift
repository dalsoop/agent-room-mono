import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomUsageText — 토큰 사용량 및 한도 포맷터")
struct RoomUsageTextTests {
    @Test("used 가 nil 이면 기본 미계측 문구를 반환한다")
    func testNilUsedReturnsUnknownText() {
        #expect(RoomUsageText.format(used: nil, limit: nil) == "미계측")
        #expect(RoomUsageText.format(used: nil, limit: 160_000, unknownText: "unknown") == "unknown")
    }

    @Test("used 와 limit 이 있으면 쉼표 포맷과 토큰/한도 문구를 반환한다")
    func testUsedAndLimit() {
        let text = RoomUsageText.format(used: 1234, limit: 160000)
        #expect(text == "토큰 1,234 / 한도 160,000")
    }

    @Test("estimated 가 true 이면 ≈ 접두사가 붙는다")
    func testEstimatedPrefix() {
        let text = RoomUsageText.format(used: 1234, limit: 160000, estimated: true)
        #expect(text == "≈토큰 1,234 / 한도 160,000")
    }

    @Test("limit 이 nil 이면 토큰 사용량만 표기된다")
    func testLimitNil() {
        let text = RoomUsageText.format(used: 5678, limit: nil)
        #expect(text == "토큰 5,678")

        let estText = RoomUsageText.format(used: 5678, limit: nil, estimated: true)
        #expect(estText == "≈토큰 5,678")
    }

    @Test("RoomUsage 구조체 오버로드 동작 검증")
    func testRoomUsageOverload() {
        let usage = RoomUsage(used: 2500, handoffAt: 200000, isEstimated: false)
        #expect(RoomUsageText.format(usage: usage) == "토큰 2,500 / 한도 200,000")

        let estUsage = RoomUsage(used: 2500, handoffAt: 200000, isEstimated: true)
        #expect(RoomUsageText.format(usage: estUsage) == "≈토큰 2,500 / 한도 200,000")

        let nilUsage = RoomUsage(used: nil, handoffAt: 0)
        #expect(RoomUsageText.format(usage: nilUsage) == "미계측")
    }
}
