import Foundation

/// 방(Room) 수명 주기 관리 및 종료 경로의 자격증명 정리 결속.
/// 방이 close, vacate, cleanup, dismantle 될 때 방 state 폴더에 복사되었던
/// 자격증명 사본(credentials, 토큰 등)을 안전하게 삭제(unlink/wipe)한다.
public enum RoomLifecycle {
    /// 방 닫기(`close`) 시 자격증명 사본을 안전하게 삭제(wipe/unlink)한다.
    @discardableResult
    public static func close(roomURL: URL) -> Bool {
        AgentCredentialInjector.wipe(roomURL: roomURL)
    }

    /// 방 비우기(`vacate`) 시 자격증명 사본을 안전하게 삭제(wipe/unlink)한다.
    @discardableResult
    public static func vacate(roomURL: URL) -> Bool {
        AgentCredentialInjector.wipe(roomURL: roomURL)
    }

    /// 방 수명 정리(`cleanup`) 시 자격증명 사본을 안전하게 삭제(wipe/unlink)한다.
    @discardableResult
    public static func cleanup(roomURL: URL) -> Bool {
        AgentCredentialInjector.wipe(roomURL: roomURL)
    }

    /// 방 해체(`dismantle`) 시 자격증명 사본을 안전하게 삭제(wipe/unlink)한다.
    @discardableResult
    public static func dismantle(roomURL: URL) -> Bool {
        AgentCredentialInjector.wipe(roomURL: roomURL)
    }
}

/// 계약 및 표기 일관성을 위한 별칭
public typealias RoomLifeCycle = RoomLifecycle
public typealias RoomOperations = RoomLifecycle
