import Foundation
import RoomKit
import StateRootKit

public enum RoomOpenStep: String, CaseIterable, Sendable {
    case specLoad = "spec-load"
    case complianceGate = "compliance-gate"
    case assembleFolder = "assemble-folder"
    case credentialSeed = "credential-seed"
    case daemonSession = "daemon-session"
    case ledgerOccupy = "ledger-occupy"
    case ledgerOccupySuccessor = "ledger-occupy-successor"
    case printRoomMarkdown = "print-ROOM.md"

    public static let ledgerLookup = RoomOpenStep.specLoad
}

public struct RoomVerdictStatus: Equatable, Sendable {
    public var runnable: Bool
    public var reason: String

    public init(runnable: Bool, reason: String) {
        self.runnable = runnable
        self.reason = reason
    }
}

public struct RoomOpenedSession: Equatable, Sendable {
    public var sessionID: String
    public var reused: Bool
    public var seatbelt: Bool
    public var sessionRole: String
    public var predecessorSession: String?
    public var ledger: String?
    public var network: RoomNetworkBinding

    public init(
        sessionID: String,
        reused: Bool,
        seatbelt: Bool,
        sessionRole: String = RoomSessionRole.predecessor.rawValue,
        predecessorSession: String? = nil,
        ledger: String? = nil,
        network: RoomNetworkBinding = RoomNetworkBinding(wall: .closed)
    ) {
        self.sessionID = sessionID
        self.reused = reused
        self.seatbelt = seatbelt
        self.sessionRole = sessionRole
        self.predecessorSession = predecessorSession
        self.ledger = ledger
        self.network = network
    }
}

public struct RoomListedSession: Equatable, Sendable {
    public var sessionID: String
    public var roomDir: String
    public var sessionRole: String
    public var exitCode: Int?
    public var recovered: Bool

    public init(
        sessionID: String,
        roomDir: String,
        sessionRole: String = "",
        exitCode: Int? = nil,
        recovered: Bool = false
    ) {
        self.sessionID = sessionID
        self.roomDir = roomDir
        self.sessionRole = sessionRole
        self.exitCode = exitCode
        self.recovered = recovered
    }

    public var isAlive: Bool {
        exitCode == nil && !recovered
    }
}

public protocol CredentialSeeding: Sendable {
    func seed(tool: AgentRoomTool, roomURL: URL) -> AgentCredentialInjector.SeedOutcome
    func unseed(tool: AgentRoomTool, roomURL: URL) -> Bool
    func unseedAll(roomURL: URL) -> Bool
}

extension CredentialSeeding {
    public func unseedAll(roomURL: URL) -> Bool {
        AgentCredentialInjector.unseedAll(roomURL: roomURL)
    }
}

public struct LiveCredentialSeeder: CredentialSeeding {
    public init() {}

    public func seed(tool: AgentRoomTool, roomURL: URL) -> AgentCredentialInjector.SeedOutcome {
        AgentCredentialInjector.seed(tool: tool, roomURL: roomURL)
    }

    public func unseed(tool: AgentRoomTool, roomURL: URL) -> Bool {
        AgentCredentialInjector.unseed(tool: tool, roomURL: roomURL)
    }

    public func unseedAll(roomURL: URL) -> Bool {
        AgentCredentialInjector.unseedAll(roomURL: roomURL)
    }
}

public struct RoomOpenPipelineInput: Sendable {
    public var roomID: String
    public var specURL: URL?
    public var presetFlag: String?
    public var toolFlag: String?
    public var successorFlag: Bool
    public var environment: [String: String]
    public var requestedOccupant: String?
    public var columns: Int?
    public var rows: Int?
    public var selfCLIPath: String?

    public init(
        roomID: String = "",
        specURL: URL? = nil,
        presetFlag: String? = nil,
        toolFlag: String? = nil,
        successorFlag: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        requestedOccupant: String? = nil,
        columns: Int? = nil,
        rows: Int? = nil,
        selfCLIPath: String? = nil
    ) {
        self.roomID = roomID
        self.specURL = specURL
        self.presetFlag = presetFlag
        self.toolFlag = toolFlag
        self.successorFlag = successorFlag
        self.environment = environment
        self.requestedOccupant = requestedOccupant
        self.columns = columns
        self.rows = rows
        self.selfCLIPath = selfCLIPath
    }
}

public struct RoomOpenPipelineResult: Sendable {
    public var hit: LedgerRoomHit
    public var preset: RoomWallPreset
    public var tool: AgentRoomTool
    public var spec: RoomAssemblySpec
    public var assembled: RoomAssemblyResult
    public var opened: RoomOpenedSession
    public var seatbeltProfile: String?
    public var sessionID: String
    public var occupant: String
    public var wallMode: String
    public var credentialSeed: AgentCredentialInjector.SeedOutcome
    public var verdict: RoomVerdictStatus
    public var roomMarkdown: String
    public var bannerText: String

    public init(
        hit: LedgerRoomHit,
        preset: RoomWallPreset,
        tool: AgentRoomTool,
        spec: RoomAssemblySpec,
        assembled: RoomAssemblyResult,
        opened: RoomOpenedSession,
        seatbeltProfile: String?,
        sessionID: String,
        occupant: String,
        wallMode: String,
        credentialSeed: AgentCredentialInjector.SeedOutcome,
        verdict: RoomVerdictStatus,
        roomMarkdown: String,
        bannerText: String
    ) {
        self.hit = hit
        self.preset = preset
        self.tool = tool
        self.spec = spec
        self.assembled = assembled
        self.opened = opened
        self.seatbeltProfile = seatbeltProfile
        self.sessionID = sessionID
        self.occupant = occupant
        self.wallMode = wallMode
        self.credentialSeed = credentialSeed
        self.verdict = verdict
        self.roomMarkdown = roomMarkdown
        self.bannerText = bannerText
    }
}
