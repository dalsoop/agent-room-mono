import Foundation
import os

/// 방 쓰기 작업의 단일 직렬 큐 (자급자족, 외부 CLI 의존성 없음).
public final class RoomQueue: Sendable {
    private let serial: DispatchQueue
    private let queued = OSAllocatedUnfairLock(initialState: 0)
    private let requestsLock = OSAllocatedUnfairLock(initialState: [RoomRequest]())

    public init() {
        self.serial = DispatchQueue(label: "net.ranode.agent-room-terminal.room-queue")
    }

    /// 호환성용 생성자
    public convenience init(environment: [String: String]) {
        self.init()
    }

    public var queuedCount: Int { queued.withLock { $0 } }
    public var lastRetryCount: Int { 0 }
    public var submittedRequests: [RoomRequest] { requestsLock.withLock { $0 } }

    public func submit(
        _ request: RoomRequest,
        by authority: RoomAuthority
    ) async -> RoomReply {
        if let error = RoomGate.reject(request, by: authority) {
            return .failure(error)
        }
        if let error = Self.validate(request) {
            return .failure(error)
        }
        return await withCheckedContinuation { continuation in
            queued.withLock { count in
                count += 1
                serial.async {
                    self.requestsLock.withLock { $0.append(request) }
                    continuation.resume(returning: .success(#"{"ok":true}"#))
                }
            }
        }
    }

    public func recordOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: RoomAuthority
    ) async throws {
        let request = RoomRequest.occupy(
            planID: plan,
            roomID: room,
            occupant: occupant,
            handle: session,
            successor: false,
            wallMode: wallMode
        )
        try unwrap(await submit(request, by: authority))
    }

    public func recordSuccessorOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: RoomAuthority
    ) async throws {
        let request = RoomRequest.occupy(
            planID: plan,
            roomID: room,
            occupant: occupant,
            handle: session,
            successor: true,
            wallMode: wallMode
        )
        try unwrap(await submit(request, by: authority))
    }

    public func vacate(
        plan: String,
        room: String,
        reason: String,
        by authority: RoomAuthority
    ) async throws {
        let request = RoomRequest.vacate(planID: plan, roomID: room, reason: reason)
        try unwrap(await submit(request, by: authority))
    }

    public func recordClose(
        plan: String,
        workdir: String,
        by authority: RoomAuthority
    ) async throws {
        let request = RoomRequest.tick(
            planID: plan,
            roomID: authority.seatedRoomID,
            workdir: workdir
        )
        try unwrap(await submit(request, by: authority))
    }

    public func spawnChild(
        task: String,
        verify: String,
        handle: String,
        occupant: String,
        workdir: String,
        tenant: String,
        by authority: RoomAuthority
    ) async throws -> String {
        let newID = UUID().uuidString.lowercased()
        let request = RoomRequest.spawnRoom(
            roomID: authority.seatedRoomID,
            task: task,
            verify: verify,
            handle: handle,
            occupant: occupant,
            workdir: workdir,
            tenant: tenant
        )
        let reply = await submit(request, by: authority)
        _ = try unwrap(reply)
        return newID
    }

    private static func validate(_ request: RoomRequest) -> RoomError? {
        switch request {
        case let .occupy(planID, _, _, _, _, wallMode):
            return RoomField.requirePlanID(planID) ?? RoomField.requireWallMode(wallMode)
        case let .handover(planID, _, state):
            return RoomField.requirePlanID(planID) ?? RoomField.requireHandoverState(state)
        case let .vacate(planID, _, _):
            return RoomField.requirePlanID(planID)
        case let .tick(planID, _, _):
            return RoomField.requirePlanID(planID)
        case .spawnRoom:
            return nil
        }
    }

    @discardableResult
    private func unwrap(_ reply: RoomReply) throws -> String {
        if let error = reply.error { throw error }
        guard reply.ok, let result = reply.result else {
            throw RoomError.jsonMissing
        }
        return result
    }
}

public typealias LedgerQueue = RoomQueue
