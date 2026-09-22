import Foundation

/// 방 작업 및 세션 상태 실패 타입.
public enum RoomError: Error, Sendable, Equatable, LocalizedError {
    case foreignRoom
    case commandFailed(exit: Int32, stderr: String)
    case jsonMissing
    case jsonInvalid
    case roomIDMissing
    case invalidPlanID
    case invalidWallMode
    case invalidHandoverState

    public var errorDescription: String? {
        switch self {
        case .foreignRoom:
            return "room queue refused: room is neither this session's room nor its child"
        case let .commandFailed(exit, stderr):
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "room command failed (exit \(exit)): \(reason.isEmpty ? "no stderr" : reason)"
        case .jsonMissing:
            return "room reply had no JSON"
        case .jsonInvalid:
            return "room reply JSON was invalid"
        case .roomIDMissing:
            return "room reply had no room id"
        case .invalidPlanID:
            return "plan id must be a full UUID"
        case .invalidWallMode:
            return "wall mode must be full|hookOnly"
        case .invalidHandoverState:
            return "handover state must be simulating|passed|failed"
        }
    }
}

public typealias LedgerError = RoomError

/// 방 핸드오버 상태
public enum RoomHandoverState: String, Codable, Sendable, Equatable {
    case none
    case simulating
    case passed
    case failed
}

/// 방 점유·인계·닫기 쓰기 요청 한 건.
public enum RoomRequest: Sendable, Equatable {
    case occupy(
        planID: String,
        roomID: String,
        occupant: String,
        handle: String?,
        successor: Bool,
        wallMode: String
    )
    case handover(planID: String, roomID: String, state: String)
    case vacate(planID: String, roomID: String, reason: String)
    case tick(planID: String, roomID: String, workdir: String?)
    case spawnRoom(
        roomID: String,
        task: String,
        verify: String,
        handle: String,
        occupant: String,
        workdir: String,
        tenant: String
    )

    public var roomID: String {
        switch self {
        case let .occupy(_, roomID, _, _, _, _): return roomID
        case let .handover(_, roomID, _): return roomID
        case let .vacate(_, roomID, _): return roomID
        case let .tick(_, roomID, _): return roomID
        case let .spawnRoom(roomID, _, _, _, _, _, _): return roomID
        }
    }

    public var planID: String {
        switch self {
        case let .occupy(planID, _, _, _, _, _): return planID
        case let .handover(planID, _, _): return planID
        case let .vacate(planID, _, _): return planID
        case let .tick(planID, _, _): return planID
        case .spawnRoom: return ""
        }
    }
}

public typealias LedgerRequest = RoomRequest

/// 요청자 세션이 앉은 방과, 그 방이 연 자식 방.
public struct RoomAuthority: Sendable, Equatable {
    public enum Scope: Sendable, Equatable {
        case room
        case commandRoom
    }

    public var sessionID: String
    public var seatedRoomID: String
    public var childRoomIDs: Set<String>
    public var scope: Scope

    public init(
        sessionID: String,
        seatedRoomID: String,
        childRoomIDs: Set<String>,
        scope: Scope
    ) {
        self.sessionID = sessionID
        self.seatedRoomID = seatedRoomID
        self.childRoomIDs = childRoomIDs
        self.scope = scope
    }

    public static func commandRoom(sessionID: String, seatedRoomID: String) -> RoomAuthority {
        RoomAuthority(
            sessionID: sessionID,
            seatedRoomID: seatedRoomID,
            childRoomIDs: [],
            scope: .commandRoom
        )
    }
}

public typealias LedgerAuthority = RoomAuthority

/// 방 작업 쓰기 결과.
public struct RoomReply: Sendable, Equatable {
    public var ok: Bool
    public var result: String?
    public var error: RoomError?

    public init(ok: Bool, result: String?, error: RoomError?) {
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(_ result: String) -> RoomReply {
        RoomReply(ok: true, result: result, error: nil)
    }

    public static func failure(_ error: RoomError) -> RoomReply {
        RoomReply(ok: false, result: nil, error: error)
    }
}

public typealias LedgerReply = RoomReply

enum RoomGate {
    static func reject(_ request: RoomRequest, by authority: RoomAuthority) -> RoomError? {
        if authority.scope == .commandRoom { return nil }
        let roomID = request.roomID
        if roomID == authority.seatedRoomID { return nil }
        if authority.childRoomIDs.contains(roomID) { return nil }
        return .foreignRoom
    }
}

typealias LedgerGate = RoomGate

enum RoomField {
    static let wallModes: Set<String> = ["full", "hookOnly"]
    static let handoverStates: Set<String> = ["simulating", "passed", "failed"]

    static func requirePlanID(_ raw: String) -> RoomError? {
        UUID(uuidString: raw) == nil ? .invalidPlanID : nil
    }

    static func requireWallMode(_ raw: String) -> RoomError? {
        wallModes.contains(raw) ? nil : .invalidWallMode
    }

    static func requireHandoverState(_ raw: String) -> RoomError? {
        handoverStates.contains(raw) ? nil : .invalidHandoverState
    }
}

typealias LedgerField = RoomField
