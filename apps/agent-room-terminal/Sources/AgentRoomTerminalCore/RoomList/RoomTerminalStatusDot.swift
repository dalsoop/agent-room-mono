import Foundation

public enum RoomTerminalStatusDot: String, Sendable, CaseIterable, Equatable {
    case executing    // 실행 중 (초록)
    case waitingInput // 입력 대기 (주황)
    case completed    // 완료 (회색)
    case error        // 오류 (빨강)

    /// 순수 함수: 상태 점 판정
    /// - attach 오류 = 오류
    /// - 프로세스 종료 또는 세션 없음 = 완료
    /// - 벨 또는 진행률 대기 이벤트 = 입력 대기
    /// - 5초 내 수신 = 실행 중
    /// - 5~30초 사이 = 실행 중 유지
    /// - 30초 무출력 = 입력 대기
    public static func judge(
        hasSession: Bool,
        lastByteReceivedAt: Date?,
        hasWaitingEvent: Bool = false,
        processTerminated: Bool = false,
        hasAttachError: Bool = false,
        now: Date = Date()
    ) -> RoomTerminalStatusDot {
        if hasAttachError {
            return .error
        }
        if processTerminated || !hasSession {
            return .completed
        }
        if hasWaitingEvent {
            return .waitingInput
        }
        if let lastByte = lastByteReceivedAt {
            let elapsed = now.timeIntervalSince(lastByte)
            if elapsed <= 30.0 {
                return .executing
            } else {
                return .waitingInput
            }
        }
        return .waitingInput
    }

    /// RoomStatus 투영 기반 상태 점 판정 순수 함수
    public static func judge(
        status: RoomStatus,
        lastByteReceivedAt: Date?,
        hasWaitingEvent: Bool = false,
        hasAttachError: Bool = false,
        now: Date = Date()
    ) -> RoomTerminalStatusDot {
        if hasAttachError {
            return .error
        }
        switch status.phase {
        case .closed, .exited, .created, .approved, .rejected, .gated, .escalated, .blocked:
            return .completed
        case .open, .occupied:
            if hasWaitingEvent {
                return .waitingInput
            }
            if let lastByte = lastByteReceivedAt {
                let elapsed = now.timeIntervalSince(lastByte)
                if elapsed <= 30.0 {
                    return .executing
                } else {
                    return .waitingInput
                }
            }
            return .waitingInput
        }
    }
}
