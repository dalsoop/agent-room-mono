import Foundation
@_exported import RoomKit

/// 벽 프리셋 — 규칙 본문은 `RoomKit`.
public typealias RoomWallPreset = RoomKit.RoomWallPreset

/// 원장 `RoomWalls` 와 같은 값 — 네트워크 벽 타입은 `RoomKit`.
public typealias RoomWallSnapshot = RoomKit.RoomWalls

public struct RoomBlueprintSnapshot: Equatable, Sendable {
    public var task: String
    public var verdict: String
    public var brief: [String]
    public var toolbelt: [String]
    public var preset: RoomWallPreset
    public var walls: RoomWallSnapshot
    /// 방 안에서 띄울 수 있는 에이전트 CLI(claude·codex·grok·agy). toolbelt 와 달리 함대 앱이 아니라 준수 판정을 하지 않는다.
    public var agentTools: [String]
    /// 배치도의 작업 디렉터리(worktree). 상대 writePaths 는 이 디렉터리 기준으로 풀린다. nil 이면 방 폴더 기준.
    public var workdir: String?

    public init(
        task: String,
        verdict: String,
        brief: [String] = [],
        toolbelt: [String] = [],
        preset: RoomWallPreset = .toolbelt,
        walls: RoomWallSnapshot = RoomWallSnapshot(),
        agentTools: [String] = [],
        workdir: String? = nil
    ) {
        self.task = task
        self.verdict = verdict
        self.brief = brief
        self.toolbelt = toolbelt
        self.preset = preset
        self.walls = walls
        self.agentTools = agentTools
        self.workdir = workdir
    }

    public func makeWalls() -> RoomWalls {
        var base = RoomWalls.preset(preset, toolbelt: toolbelt)
        base.filesystem.allowWrite = walls.writePaths
        base.network = walls.network
        return base
    }
}

public struct RoomTenantPolicy: Equatable, Sendable {
    public var stateRoot: String
    public var wikiWorld: String

    public init(stateRoot: String, wikiWorld: String) {
        self.stateRoot = stateRoot
        self.wikiWorld = wikiWorld
    }
}



public struct RoomParentRef: Equatable, Sendable {
    public var roomID: String
    public var slug: String
    public var preset: RoomWallPreset
    public var walls: RoomWallSnapshot
    public var binNames: Set<String>
    public var folderURL: URL

    public init(
        roomID: String,
        slug: String,
        preset: RoomWallPreset,
        walls: RoomWallSnapshot,
        binNames: Set<String>,
        folderURL: URL
    ) {
        self.roomID = roomID
        self.slug = slug
        self.preset = preset
        self.walls = walls
        self.binNames = binNames
        self.folderURL = folderURL
    }
}

public struct RoomAssemblySpec: Sendable {
    public var roomID: String
    public var slug: String
    public var tenantSlug: String
    public var layoutID: String
    public var parent: RoomParentRef?
    public var blueprint: RoomBlueprintSnapshot
    public var tenantPolicy: RoomTenantPolicy
    public var budget: RoomBudgetSnapshot
    public var compliance: any ComplianceChecking
    public var sourceHashGate: any SourceHashChecking
    public var environment: [String: String]
    public var homeDirectory: String
    public var selfCLIPath: String?

    public init(
        roomID: String,
        slug: String,
        tenantSlug: String,
        layoutID: String,
        parent: RoomParentRef? = nil,
        blueprint: RoomBlueprintSnapshot,
        tenantPolicy: RoomTenantPolicy,
        budget: RoomBudgetSnapshot,
        compliance: any ComplianceChecking,
        sourceHashGate: (any SourceHashChecking)? = nil,
        environment: [String: String],
        homeDirectory: String,
        selfCLIPath: String? = nil
    ) {
        self.roomID = roomID
        self.slug = slug
        self.tenantSlug = tenantSlug
        self.layoutID = layoutID
        self.parent = parent
        self.blueprint = blueprint
        self.tenantPolicy = tenantPolicy
        self.budget = budget
        self.compliance = compliance
        self.sourceHashGate = sourceHashGate ?? DefaultSourceHashGate(environment: environment, homeDirectory: homeDirectory)
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.selfCLIPath = selfCLIPath
    }

    public var tenantID: String {
        tenantSlug.hasPrefix("tenant:") ? tenantSlug : "tenant:\(tenantSlug)"
    }

    public var cleanTenantSlug: String {
        tenantSlug.hasPrefix("tenant:") ? String(tenantSlug.dropFirst(7)) : tenantSlug
    }

    public func makeRoomSpec(launch: RoomLaunch? = nil) -> RoomSpec {
        RoomSpec(
            roomID: UUID(uuidString: roomID) ?? UUID(),
            tenant: tenantID,
            task: blueprint.task,
            verdict: blueprint.verdict,
            workdir: blueprint.workdir,
            walls: blueprint.makeWalls(),
            launch: launch,
            executionPolicy: RoomExecutionPolicy(
                lineage: RoomLineage(
                    planID: layoutID,
                    blueprintSlug: slug,
                    parentRoomID: parent.flatMap { UUID(uuidString: $0.roomID) }
                ),
                budget: budget
            )
        )
    }
}

public struct RoomAssemblyResult: Equatable, Sendable {
    public var roomURL: URL
    public var excludedTools: [String]
    public var linkedTools: [String]

    public init(roomURL: URL, excludedTools: [String], linkedTools: [String]) {
        self.roomURL = roomURL
        self.excludedTools = excludedTools
        self.linkedTools = linkedTools
    }
}

public enum RoomAssemblyError: Error, Equatable, LocalizedError {
    case invalidSlug(String)
    case childPresetExceedsParent(child: RoomWallPreset, parent: RoomWallPreset)
    case childWallsExceedParent(paths: [String])
    case childBinExceedsParent(names: [String])
    case posixToolMissing(String)
    case selfCLIMissing
    case isolationCLIMissing
    case complianceCheckFailed(cli: String, stderr: String)
    case complianceJSONInvalid
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSlug(let slug):
            return "room slug is not kebab-case: \(slug)"
        case .childPresetExceedsParent(let child, let parent):
            return "child preset \(child.rawValue) exceeds parent \(parent.rawValue)"
        case .childWallsExceedParent(let paths):
            return "child walls exceed parent: \(paths.joined(separator: ", "))"
        case .childBinExceedsParent(let names):
            return "child bin is not a subset of parent bin: \(names.joined(separator: ", "))"
        case .posixToolMissing(let name):
            return "posix base-bin tool missing: \(name)"
        case .selfCLIMissing:
            return "agent-room-terminal executable not found"
        case .isolationCLIMissing:
            return "agent-tenant-isolation-manager not on PATH"
        case .complianceCheckFailed(let cli, let stderr):
            return "compliance check failed (\(cli)): \(stderr)"
        case .complianceJSONInvalid:
            return "compliance JSON was not readable"
        case .toolNotFound(let name):
            return "toolbelt CLI not on PATH: \(name)"
        }
    }
}
