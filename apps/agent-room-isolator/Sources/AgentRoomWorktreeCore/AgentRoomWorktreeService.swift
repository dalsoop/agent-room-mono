import Foundation
import CommandKit
import AppPathsKit

public enum AgentRoomWorktreeError: Error, Sendable, Equatable {
    case taskEmpty
    case trivialVerify(String)
    case bindNotFound(String)
    case commandFailed(String)
    case worktreeCreateFailed(String)
    case spawnRoomFailed(String)
}

public struct AgentRoomWorktreeService: Sendable {
    private let runner: CommandRunning
    private let environment: [String: String]
    private let files: RoomFiles

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        files: RoomFiles = RoomFiles()
    ) {
        self.runner = runner
        self.environment = environment
        self.files = files
    }

    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: RoomWorktreePaths.sqliteFile(environment: environment))
        let dir = RoomWorktreePaths.stateDirectory(environment: environment)
        try files.createDirectory(at: dir)
    }

    public func status() async throws -> String {
        let n = try await list().count
        return "binds:\(n)"
    }

    public func list() async throws -> [RoomWorktreeBind] {
        let ledger = try await loadLedgerBinds()
        if !ledger.isEmpty { return ledger }
        return try store().load()
    }

    public func show(roomID: String) async throws -> RoomWorktreeBind {
        if let hit = try await list().first(where: { $0.roomID == roomID }) {
            return hit
        }
        return try store().find(roomID: roomID)
    }

    public func bind(_ bind: RoomWorktreeBind) throws -> RoomWorktreeBind {
        _ = try store().upsert(bind)
        try persistSides(bind)
        return bind
    }

    public func emitMd(roomID: String, wallPreset: String = "toolbelt", network: Bool = false) async throws -> [String] {
        let bind = try await show(roomID: roomID)
        return try writeDocuments(bind: bind, wallPreset: wallPreset, network: network)
    }

    public func worktreeExists(_ bind: RoomWorktreeBind) -> Bool {
        files.fileExists(atPath: bind.worktreePath)
    }

    public func documentSnapshots(roomID: String, tenantID: String? = nil) throws -> [RoomDocumentSnapshot] {
        let tid = tenantID ?? (try? store().find(roomID: roomID))?.tenantID
        let roomDir = RoomWorktreePaths.roomDirectory(id: roomID, tenantID: tid, environment: environment)
        return RoomBirthDocuments.names.map { name in
            let url = roomDir.appendingPathComponent(name)
            let exists = files.fileExists(atPath: url.path)
            let preview: String
            if exists {
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    preview = text.split(separator: "\n").prefix(8).joined(separator: "\n")
                } catch {
                    preview = ""
                }
            } else {
                preview = ""
            }
            return RoomDocumentSnapshot(name: name, path: url.path, exists: exists, preview: preview)
        }
    }

    public func doctor() async throws -> RoomDoctorReport {
        let binds = try await list()
        var findings: [String] = []
        for bind in binds {
            findings.append(contentsOf: Self.doctorLines(try await trace(roomID: bind.roomID)))
        }
        return RoomDoctorReport(ok: findings.isEmpty, bindCount: binds.count, findings: findings)
    }

    static func doctorLines(_ t: RoomTrace) -> [String] {
        let id = t.bind.roomID
        let checks: [(Bool, String)] = [
            (!t.worktree.pathExists, "missing-worktree:\(id)"),
            (!t.worktree.listedByGit, "git-unlisted:\(id)"),
            (!t.worktree.markerOK, "missing-marker:\(id)"),
            (!t.ledger.ok, "missing-ledger:\(id):\(t.ledger.error)"),
        ]
        let missingMD = t.documents.filter { !$0.exists }.map { "missing-md:\(id):\($0.name)" }
        return checks.compactMap { $0.0 ? $0.1 : nil } + missingMD
    }

    public func trace(roomID: String) async throws -> RoomTrace {
        let bind = try await show(roomID: roomID)
        let documents = try documentSnapshots(roomID: bind.roomID, tenantID: bind.tenantID)
        let worktree = await probeWorktree(bind)
        let ledger = await probeLedger(bind)
        let ok = worktree.pathExists && worktree.markerOK && ledger.ok
            && documents.allSatisfy(\.exists)
        return RoomTrace(bind: bind, ledger: ledger, worktree: worktree, documents: documents, ok: ok)
    }

    public func provision(_ request: ProvisionRequest) async throws -> ProvisionResult {
        try RoomConcept.validate(task: request.task, verify: request.verify)
        let slug = RoomConcept.slug(from: request.name.isEmpty ? request.task : request.name, fallback: "room")
        let repo = (request.repoPath as NSString).standardizingPath
        let worktree = (repo as NSString).appendingPathComponent(".worktrees/\(slug)")
        let planned = Self.plannedCommands(repo: repo, slug: slug, worktree: worktree, spawn: request.spawn)
        guard !request.dryRun else {
            return dryRunResult(request: request, slug: slug, repo: repo, worktree: worktree, planned: planned)
        }
        return try await liveProvision(request, slug: slug, repo: repo, worktree: worktree, planned: planned)
    }

    static func plannedCommands(repo: String, slug: String, worktree: String, spawn: Bool) -> [String] {
        let create = "\(RoomWorktreePaths.env) agent-worktree-control-terminal create \(repo) \(slug) --inside --base origin/main"
        guard spawn else { return [create] }
        return [create, "spawn-room --waiting --workdir \(worktree)"]
    }

    func dryRunResult(
        request: ProvisionRequest, slug: String, repo: String, worktree: String, planned: [String]
    ) -> ProvisionResult {
        let bind = RoomWorktreeBind(
            roomID: "dry-run",
            planID: "dry-run",
            slug: slug,
            task: request.task,
            verify: request.verify,
            worktreePath: worktree,
            branch: slug,
            repoPath: repo,
            tenantID: request.tenantID,
            createdAt: Date()
        )
        return ProvisionResult(dryRun: true, bind: bind, documents: RoomBirthDocuments.names, planned: planned)
    }

    func liveProvision(
        _ request: ProvisionRequest, slug: String, repo: String, worktree: String, planned: [String]
    ) async throws -> ProvisionResult {
        try await createWorktree(repo: repo, name: slug)
        let ids: (roomID: String, planID: String)
        if request.spawn {
            ids = try await spawnRoom(request, worktree: worktree)
        } else {
            ids = (UUID().uuidString, UUID().uuidString)
        }
        let bind = RoomWorktreeBind(
            roomID: ids.roomID,
            planID: ids.planID,
            slug: slug,
            task: request.task,
            verify: request.verify,
            worktreePath: worktree,
            branch: slug,
            repoPath: repo,
            tenantID: request.tenantID,
            createdAt: Date()
        )
        _ = try store().upsert(bind)
        try persistSides(bind)
        let docs = try writeDocuments(bind: bind, wallPreset: request.network ? "open" : "toolbelt", network: request.network)
        try linkRoomWorktree(bind)
        return ProvisionResult(dryRun: false, bind: bind, documents: docs, planned: planned)
    }

    private func store() -> BindStore {
        BindStore(url: RoomWorktreePaths.stateFile("binds.json", environment: environment), files: files)
    }

    private func loadLedgerBinds() async throws -> [RoomWorktreeBind] {
        let r = await runner.run(RoomWorktreePaths.env, ["agent-work-todo", "placement", "list", "--json"])
        guard r.ok else { return [] }
        return PlacementListJSON.parse(r.stdout).map {
            RoomSpecEnrichment.apply($0, environment: environment)
        }
    }

    private func writeDocuments(bind: RoomWorktreeBind, wallPreset: String, network: Bool) throws -> [String] {
        let roomDir = RoomWorktreePaths.roomDirectory(id: bind.roomID, tenantID: bind.tenantID, environment: environment)
        try files.createDirectory(at: roomDir)
        var written: [String] = []
        for name in RoomBirthDocuments.names {
            let body = RoomBirthDocuments.render(name: name, bind: bind, wallPreset: wallPreset, network: network)
            let url = roomDir.appendingPathComponent(name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            written.append(url.path)
        }
        return written
    }

    private func linkRoomWorktree(_ bind: RoomWorktreeBind) throws {
        let link = RoomWorktreePaths.roomDirectory(id: bind.roomID, tenantID: bind.tenantID, environment: environment)
            .appendingPathComponent("worktree", isDirectory: true)
        guard !files.fileExists(atPath: link.path) else { return }
        try files.createSymbolicLink(atPath: link.path, withDestinationPath: bind.worktreePath)
    }

    private func createWorktree(repo: String, name: String) async throws {
        let r = await runner.run(
            RoomWorktreePaths.env,
            ["agent-worktree-control-terminal", "create", repo, name, "--inside", "--base", "origin/main"]
        )
        guard r.ok else {
            let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentRoomWorktreeError.worktreeCreateFailed(detail.isEmpty ? "exit \(r.exitCode)" : detail)
        }
    }

    private func spawnRoom(_ request: ProvisionRequest, worktree: String) async throws -> (roomID: String, planID: String) {
        var args = [
            "agent-work-todo", "spawn-room",
            "--task", request.task,
            "--verify", request.verify,
            "--occupant", request.occupant,
            "--quote", request.quote,
            "--workdir", worktree,
            "--waiting",
            "--json",
            "--tenant", request.tenantID,
        ]
        if request.network { args.append("--network") }
        let r = await runner.run(RoomWorktreePaths.env, args)
        guard r.ok else {
            let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentRoomWorktreeError.spawnRoomFailed(detail.isEmpty ? "exit \(r.exitCode)" : detail)
        }
        guard let parsed = SpawnRoomJSON.parse(r.stdout) else {
            throw AgentRoomWorktreeError.spawnRoomFailed("spawn-room json missing roomID/planID")
        }
        return parsed
    }

    private func persistSides(_ bind: RoomWorktreeBind) throws {
        let roomDir = RoomWorktreePaths.roomDirectory(id: bind.roomID, tenantID: bind.tenantID, environment: environment)
        try files.createDirectory(at: roomDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bind)
        try data.write(to: roomDir.appendingPathComponent("bind.json"), options: .atomic)
    }

    private func probeWorktree(_ bind: RoomWorktreeBind) async -> WorktreeTrace {
        let exists = files.fileExists(atPath: bind.worktreePath)
        let markerURL = RoomWorktreePaths.roomDirectory(id: bind.roomID, tenantID: bind.tenantID, environment: environment)
            .appendingPathComponent("bind.json")
        var markerOK = false
        do {
            let data = try Data(contentsOf: markerURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let obj = try decoder.decode(RoomWorktreeBind.self, from: data)
            markerOK = obj.roomID == bind.roomID && obj.planID == bind.planID
                && obj.worktreePath == bind.worktreePath
        } catch {
            markerOK = false
        }
        let r = await runner.run(RoomWorktreePaths.env, [
            "git", "-C", bind.repoPath, "worktree", "list", "--porcelain",
        ])
        let listed = GitWorktreeList.lists(path: bind.worktreePath, porcelain: r.stdout)
        return WorktreeTrace(
            pathExists: exists,
            listedByGit: listed.listed,
            markerOK: markerOK,
            branch: listed.branch.isEmpty ? bind.branch : listed.branch
        )
    }

    private func probeLedger(_ bind: RoomWorktreeBind) async -> LedgerTrace {
        if bind.planID.isEmpty || bind.planID == "dry-run" {
            return LedgerTrace(
                ok: false, planID: bind.planID, roomID: bind.roomID,
                state: "", occupant: "", error: "no-plan"
            )
        }
        let r = await runner.run(RoomWorktreePaths.env, [
            "agent-work-todo", "placement", "show", bind.planID, "--json",
        ])
        if !r.ok {
            let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return LedgerTrace(
                ok: false, planID: bind.planID, roomID: bind.roomID,
                state: "", occupant: "",
                error: detail.isEmpty ? "placement-show-failed" : detail
            )
        }
        return PlacementShowJSON.parse(
            stdout: r.stdout, expectedRoomID: bind.roomID, planID: bind.planID
        )
    }
}
