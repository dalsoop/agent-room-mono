import Foundation
import RoomKit

/// 방의 벽 — 쓰기 경로·네트워크·기준 작업 디렉터리.
public struct RoomOpenWalls: Sendable, Equatable {
    public var writePaths: [String]
    public var network: NetworkWall
    public var workdir: String?

    public init(
        writePaths: [String],
        network: NetworkWall,
        workdir: String? = nil
    ) {
        self.writePaths = writePaths
        self.network = network
        self.workdir = workdir
    }
}

public typealias LedgerRoomWalls = RoomOpenWalls

/// 방 열기 입력 정보 (구 LedgerRoomHit).
public struct RoomOpenInput: Sendable, Equatable {
    public var planID: String
    public var roomID: String
    public var slug: String
    public var tenant: String
    public var layoutID: String
    public var parentRoomID: String
    public var occupant: String
    public var occupantSession: String
    public var wallMode: String
    public var successorOccupant: String
    public var successorSession: String
    public var handoverState: String
    public var bottleSwapCount: Int
    public var task: String
    public var verdict: String
    public var brief: [String]
    public var toolbelt: [String]
    public var preset: String
    public var agentTools: [String]
    public var walls: RoomOpenWalls

    public init(
        planID: String,
        roomID: String,
        slug: String,
        tenant: String,
        layoutID: String,
        parentRoomID: String = "",
        occupant: String = "",
        occupantSession: String = "",
        wallMode: String = "full",
        successorOccupant: String = "",
        successorSession: String = "",
        handoverState: String = "none",
        bottleSwapCount: Int = 0,
        task: String,
        verdict: String = "true",
        brief: [String] = [],
        toolbelt: [String] = [],
        preset: String = "toolbelt",
        agentTools: [String] = [],
        walls: RoomOpenWalls
    ) {
        self.planID = planID
        self.roomID = roomID
        self.slug = slug
        self.tenant = tenant
        self.layoutID = layoutID
        self.parentRoomID = parentRoomID
        self.occupant = occupant
        self.occupantSession = occupantSession
        self.wallMode = wallMode
        self.successorOccupant = successorOccupant
        self.successorSession = successorSession
        self.handoverState = handoverState
        self.bottleSwapCount = bottleSwapCount
        self.task = task
        self.verdict = verdict
        self.brief = brief
        self.toolbelt = toolbelt
        self.preset = preset
        self.agentTools = agentTools
        self.walls = walls
    }

    public var writePaths: [String] { walls.writePaths }
    public var network: NetworkWall { walls.network }
    public var workdir: String? { walls.workdir }

    public init(roomSpec: RoomSpec) {
        let planID = roomSpec.lineage.planID ?? "plan"
        let slug = roomSpec.lineage.blueprintSlug ?? roomSpec.roomID.uuidString
        let toolName = roomSpec.launch?.tool.rawValue
        let agentTools = toolName.map { [$0] } ?? []
        var toolbelt: [String] = []
        if case .allowList(let list) = roomSpec.walls.executables {
            toolbelt = list
        }
        let preset: String
        if roomSpec.walls.isReadOnly {
            preset = "readOnly"
        } else if roomSpec.walls.shell == .normal {
            preset = "open"
        } else {
            preset = "toolbelt"
        }
        self.init(
            planID: planID,
            roomID: roomSpec.roomID.uuidString,
            slug: slug,
            tenant: roomSpec.tenant,
            layoutID: planID,
            parentRoomID: roomSpec.lineage.parentRoomID?.uuidString ?? "",
            occupant: "",
            occupantSession: "",
            wallMode: "full",
            successorOccupant: "",
            successorSession: "",
            handoverState: "none",
            task: roomSpec.task,
            verdict: roomSpec.verdict,
            brief: [],
            toolbelt: toolbelt,
            preset: preset,
            agentTools: agentTools,
            walls: RoomOpenWalls(
                writePaths: roomSpec.walls.filesystem.allowWrite,
                network: roomSpec.walls.network,
                workdir: roomSpec.workdir
            )
        )
    }
}

public typealias LedgerRoomHit = RoomOpenInput

public enum RoomLookupError: Error, LocalizedError, Equatable, Sendable {
    case commandFailed(String)
    case notInLedger(String)
    case roomMissing(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let stderr):
            return "lookup failed: \(stderr)"
        case .notInLedger(let id):
            return "room-id not found: \(id)"
        case .roomMissing(let id):
            return "room folder not found under ~/.tenants: \(id)"
        }
    }
}

public typealias LedgerLookupError = RoomLookupError

public protocol RoomOpenLooking: Sendable {
    func findRoom(roomID: String, environment: [String: String]) throws -> RoomOpenInput?
}

public typealias RoomLedgerLooking = RoomOpenLooking

public struct LiveRoomOpenLookup: RoomOpenLooking {
    public var environment: [String: String]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.environment = environment
    }

    public func findRoom(roomID: String, environment: [String: String]) throws -> RoomOpenInput? {
        try Self.findRoom(roomID: roomID, environment: environment)
    }

    public static func findRoom(
        roomID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RoomOpenInput? {
        guard let roomDir = RoomPaths.findRoomDirectory(roomID: roomID, tenant: nil, environment: environment) else {
            return nil
        }
        let specFile = roomDir.appendingPathComponent(RoomPaths.specFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: specFile.path) else {
            return nil
        }
        var hit = try RoomOpenInput.decode(specData: try Data(contentsOf: specFile))
        let eventLog = RoomEventLog(roomURL: roomDir)
        let status = RoomStatusProjection.reduce(events: eventLog.read().events)
        if let occupant = status.occupant {
            hit.occupant = occupant
        }
        if let sessionID = status.sessionID {
            hit.occupantSession = sessionID
        }
        return hit
    }
}

public typealias LiveRoomLedgerLookup = LiveRoomOpenLookup
public typealias LedgerLookup = LiveRoomOpenLookup

extension RoomOpenInput {
    /// `spec.json` 한 장에서 `RoomSpec` 과 work-todo 가 덧붙인 좌석 필드(toolbelt·preset·wallMode·후임)를 함께 읽는다.
    static func decode(specData data: Data) throws -> RoomOpenInput {
        let roomSpec = try JSONDecoder().decode(RoomSpec.self, from: data)
        var hit = RoomOpenInput(roomSpec: roomSpec)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let toolbelt = raw["toolbelt"] as? [String] { hit.toolbelt = toolbelt }
        if let preset = raw["preset"] as? String { hit.preset = preset }
        if let wallMode = raw["wallMode"] as? String { hit.wallMode = wallMode }
        if let successorOccupant = raw["successorOccupant"] as? String { hit.successorOccupant = successorOccupant }
        if let successorSession = raw["successorSession"] as? String { hit.successorSession = successorSession }
        if let handoverState = raw["handoverState"] as? String { hit.handoverState = handoverState }
        if let bottleSwapCount = raw["bottleSwapCount"] as? Int { hit.bottleSwapCount = bottleSwapCount }
        return hit
    }
}
