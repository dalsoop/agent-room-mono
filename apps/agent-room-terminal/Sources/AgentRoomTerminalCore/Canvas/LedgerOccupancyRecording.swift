import Foundation

/// 점유·비움 기록 훅. P1-C 이후 L4 는 L1(work-todo)을 부르지 않으므로 기본 구현은 아무것도 하지 않는다.
/// 점유 사실은 방 폴더 `events.jsonl` (RoomEventLog) 에만 남는다.
public protocol LedgerOccupancyRecording: Sendable {
    func recordOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: LedgerAuthority
    ) async throws
    func recordSuccessorOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: LedgerAuthority
    ) async throws
    func vacate(
        plan: String,
        room: String,
        reason: String,
        by authority: LedgerAuthority
    ) async throws
    func recordClose(
        plan: String,
        workdir: String,
        by authority: LedgerAuthority
    ) async throws
}

extension LedgerOccupancyRecording {
    public func recordSuccessorOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: LedgerAuthority
    ) async throws {}

    public func vacate(
        plan: String,
        room: String,
        reason: String,
        by authority: LedgerAuthority
    ) async throws {}
}

public struct NoopLedgerOccupancy: LedgerOccupancyRecording {
    public init() {}
    public func recordOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: LedgerAuthority
    ) async throws {}

    public func recordClose(plan: String, workdir: String, by authority: LedgerAuthority) async throws {}
}
