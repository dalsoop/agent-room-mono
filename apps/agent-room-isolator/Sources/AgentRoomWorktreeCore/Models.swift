import Foundation

/// FileManager 를 Core 에 붙이지 않는다. 호출마다 새 인스턴스.
public struct RoomFiles: Sendable {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager().fileExists(atPath: path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager().createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func createSymbolicLink(atPath path: String, withDestinationPath dest: String) throws {
        try FileManager().createSymbolicLink(atPath: path, withDestinationPath: dest)
    }
}

/// 방 하나와 git worktree 한 줄의 결속.
public struct RoomWorktreeBind: Sendable, Equatable, Identifiable, Codable {
    public var id: String { roomID }
    public var roomID: String
    public var planID: String
    public var slug: String
    public var task: String
    public var verify: String
    public var worktreePath: String
    public var branch: String
    public var repoPath: String
    public var tenantID: String
    public var createdAt: Date

    public init(
        roomID: String,
        planID: String,
        slug: String,
        task: String,
        verify: String,
        worktreePath: String,
        branch: String,
        repoPath: String,
        tenantID: String,
        createdAt: Date
    ) {
        self.roomID = roomID
        self.planID = planID
        self.slug = slug
        self.task = task
        self.verify = verify
        self.worktreePath = worktreePath
        self.branch = branch
        self.repoPath = repoPath
        self.tenantID = tenantID
        self.createdAt = createdAt
    }
}

/// Occupant from `--occupant`, else `FORGE_ACTOR` / `AGENT_ACTOR`. Never invents a host.
public enum OccupantIdentity: Sendable {
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for key in ["FORGE_ACTOR", "AGENT_ACTOR"] {
            guard let raw = environment[key] else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}

/// `provision` 입력. task·verify 가 방 개념이다.
public struct ProvisionRequest: Sendable, Equatable {
    public var task: String
    public var verify: String
    public var repoPath: String
    public var name: String
    public var occupant: String
    public var quote: String
    public var tenantID: String
    public var network: Bool
    public var dryRun: Bool
    public var spawn: Bool

    public init(
        task: String,
        verify: String,
        repoPath: String,
        name: String,
        occupant: String,
        quote: String,
        tenantID: String = "tenant:personal",
        network: Bool = false,
        dryRun: Bool = false,
        spawn: Bool = true
    ) {
        self.task = task
        self.verify = verify
        self.repoPath = repoPath
        self.name = name
        self.occupant = occupant
        self.quote = quote
        self.tenantID = tenantID
        self.network = network
        self.dryRun = dryRun
        self.spawn = spawn
    }
}

public struct ProvisionResult: Sendable, Equatable, Codable {
    public var dryRun: Bool
    public var bind: RoomWorktreeBind
    public var documents: [String]
    public var planned: [String]
}

public struct RoomDoctorReport: Sendable, Equatable, Codable {
    public var ok: Bool
    public var bindCount: Int
    public var findings: [String]
}

public struct LedgerTrace: Sendable, Equatable, Codable {
    public var ok: Bool
    public var planID: String
    public var roomID: String
    public var state: String
    public var occupant: String
    public var error: String
}

public struct WorktreeTrace: Sendable, Equatable, Codable {
    public var pathExists: Bool
    public var listedByGit: Bool
    public var markerOK: Bool
    public var branch: String
}

public struct RoomTrace: Sendable, Equatable, Codable {
    public var bind: RoomWorktreeBind
    public var ledger: LedgerTrace
    public var worktree: WorktreeTrace
    public var documents: [RoomDocumentSnapshot]
    public var ok: Bool
}

/// 방 폴더 MD 한 장의 화면용 스냅샷.
public struct RoomDocumentSnapshot: Sendable, Equatable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var path: String
    public var exists: Bool
    public var preview: String

    public init(name: String, path: String, exists: Bool, preview: String) {
        self.name = name
        self.path = path
        self.exists = exists
        self.preview = preview
    }
}
