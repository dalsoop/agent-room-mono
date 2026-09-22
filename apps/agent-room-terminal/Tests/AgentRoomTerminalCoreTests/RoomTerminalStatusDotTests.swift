import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomTerminalStatusDot — 상태 점 판정 순수 함수")
struct RoomTerminalStatusDotTests {
    @Test("attach 오류가 있으면 무조건 error (빨강)")
    func testAttachError() {
        let now = Date()
        let result = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: now,
            hasWaitingEvent: false,
            processTerminated: false,
            hasAttachError: true,
            now: now
        )
        #expect(result == .error)
    }

    @Test("프로세스가 종료되었거나 세션이 없으면 completed (회색)")
    func testProcessTerminatedOrNoSession() {
        let now = Date()
        let terminated = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: now,
            hasWaitingEvent: false,
            processTerminated: true,
            hasAttachError: false,
            now: now
        )
        #expect(terminated == .completed)

        let noSession = RoomTerminalStatusDot.judge(
            hasSession: false,
            lastByteReceivedAt: now,
            hasWaitingEvent: false,
            processTerminated: false,
            hasAttachError: false,
            now: now
        )
        #expect(noSession == .completed)
    }

    @Test("세션 있음 + 최근 5초 내 바이트 수신은 executing (초록)")
    func testRecentBytesExecuting() {
        let now = Date()
        let received3SecondsAgo = now.addingTimeInterval(-3.0)
        let result = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: received3SecondsAgo,
            hasWaitingEvent: false,
            processTerminated: false,
            hasAttachError: false,
            now: now
        )
        #expect(result == .executing)
    }

    @Test("세션 있음 + 벨 또는 진행률 대기 이벤트는 waitingInput (주황)")
    func testWaitingEvent() {
        let now = Date()
        let received1SecondAgo = now.addingTimeInterval(-1.0)
        let result = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: received1SecondAgo,
            hasWaitingEvent: true,
            processTerminated: false,
            hasAttachError: false,
            now: now
        )
        #expect(result == .waitingInput)
    }

    @Test("경계값(4.9s, 5.1s, 29.9s, 30.1s) 판정 검증")
    func testBoundaryThresholds() {
        let now = Date()

        // 4.9s 전 수신: executing
        let t4_9 = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: now.addingTimeInterval(-4.9),
            now: now
        )
        #expect(t4_9 == .executing)

        // 5.1s 전 수신: 5~30s 사이 실행 중 유지 -> executing
        let t5_1 = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: now.addingTimeInterval(-5.1),
            now: now
        )
        #expect(t5_1 == .executing)

        // 29.9s 전 수신: executing
        let t29_9 = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: now.addingTimeInterval(-29.9),
            now: now
        )
        #expect(t29_9 == .executing)

        // 30.1s 전 수신: 30s 무출력 -> waitingInput
        let t30_1 = RoomTerminalStatusDot.judge(
            hasSession: true,
            lastByteReceivedAt: now.addingTimeInterval(-30.1),
            now: now
        )
        #expect(t30_1 == .waitingInput)
    }
}
