import Foundation
import InteropKit
import LocalizationKit
import AgentRoomWorktreeCore

private struct DocumentEmitResult: Codable {
    var documents: [String]
}

enum DomainCommands {
    static func run(_ cmd: String, _ rest: [String]) async {
        let json = rest.contains("--json")
        do {
            try AgentRoomWorktreeService().ensureDurableStore()
            switch cmd {
            case "status":
                let text = try await AgentRoomWorktreeService().status()
                emit(["status": text], json: json) { print(text) }
            case "provision":
                try await provision(rest, json: json)
            case "bind":
                try bind(rest, json: json)
            case "emit-md":
                try await emitMd(rest, json: json)
            case "list":
                try await list(json: json)
            case "show":
                try await show(rest, json: json)
            case "doctor":
                try await doctor(json: json)
            case "trace":
                try await trace(rest, json: json)
            default:
                FileHandle.standardError.write(
                    Data((CLILocalization.format("cli.error.unknown_command", cmd) + "\n").utf8)
                )
                exit(64)
            }
        } catch {
            emitFailure(error, json: json)
            exit(1)
        }
    }

    static func provision(_ rest: [String], json: Bool) async throws {
        guard let task = option("--task", rest), let verify = option("--verify", rest),
              let repo = option("--repo", rest)
        else {
            FileHandle.standardError.write(
                Data((CLILocalization.string("cli.error.provision_required") + "\n").utf8)
            )
            exit(64)
        }
        let name = option("--name", rest) ?? RoomConcept.slug(from: task, fallback: "room")
        let occupant = requireOccupant(rest)
        let quote = option("--quote", rest) ?? task
        let tenant = requireTenant(rest)
        let request = ProvisionRequest(
            task: task,
            verify: verify,
            repoPath: repo,
            name: name,
            occupant: occupant,
            quote: quote,
            tenantID: tenant,
            network: rest.contains("--network"),
            dryRun: rest.contains("--dry-run"),
            spawn: !rest.contains("--no-spawn")
        )
        let result = try await AgentRoomWorktreeService().provision(request)
        emit(result, json: json) {
            print("room \(result.bind.roomID)")
            print("worktree \(result.bind.worktreePath)")
            for d in result.documents { print("md \(d)") }
        }
    }

    static func bind(_ rest: [String], json: Bool) throws {
        guard let room = option("--room", rest),
              let worktree = option("--worktree", rest),
              let branch = option("--branch", rest),
              let repo = option("--repo", rest)
        else {
            FileHandle.standardError.write(
                Data((CLILocalization.string("cli.error.bind_required") + "\n").utf8)
            )
            exit(64)
        }
        let bind = RoomWorktreeBind(
            roomID: room,
            planID: option("--plan", rest) ?? "",
            slug: option("--slug", rest) ?? RoomConcept.slug(from: room, fallback: "room"),
            task: option("--task", rest) ?? "",
            verify: option("--verify", rest) ?? "",
            worktreePath: worktree,
            branch: branch,
            repoPath: repo,
            tenantID: requireTenant(rest),
            createdAt: Date()
        )
        let saved = try AgentRoomWorktreeService().bind(bind)
        emit(saved, json: json) { print("bound \(saved.roomID) -> \(saved.worktreePath)") }
    }

    static func emitMd(_ rest: [String], json: Bool) async throws {
        guard let room = option("--room", rest) else {
            FileHandle.standardError.write(
                Data((CLILocalization.string("cli.error.room_required") + "\n").utf8)
            )
            exit(64)
        }
        let paths = try await AgentRoomWorktreeService().emitMd(roomID: room)
        emit(DocumentEmitResult(documents: paths), json: json) {
            for p in paths { print(p) }
        }
    }

    static func list(json: Bool) async throws {
        let binds = try await AgentRoomWorktreeService().list()
        emit(binds, json: json) {
            if binds.isEmpty {
                print(CLILocalization.string("cli.list.empty"))
                return
            }
            for b in binds {
                print("\(b.roomID)  \(b.slug)  \(b.worktreePath)")
            }
        }
    }

    static func show(_ rest: [String], json: Bool) async throws {
        guard let room = option("--room", rest) else {
            FileHandle.standardError.write(
                Data((CLILocalization.string("cli.error.room_required") + "\n").utf8)
            )
            exit(64)
        }
        let bind = try await AgentRoomWorktreeService().show(roomID: room)
        emit(bind, json: json) {
            print("room \(bind.roomID)")
            print("plan \(bind.planID)")
            print("task \(bind.task)")
            print("verify \(bind.verify)")
            print("worktree \(bind.worktreePath)")
            print("branch \(bind.branch)")
        }
    }

    static func doctor(json: Bool) async throws {
        let report = try await AgentRoomWorktreeService().doctor()
        emit(report, json: json) {
            print(report.ok ? "ok binds:\(report.bindCount)" : "fail binds:\(report.bindCount)")
            for f in report.findings { print(f) }
        }
        if !report.ok { exit(1) }
    }

    static func trace(_ rest: [String], json: Bool) async throws {
        guard let room = option("--room", rest) else {
            FileHandle.standardError.write(
                Data((CLILocalization.string("cli.error.room_required") + "\n").utf8)
            )
            exit(64)
        }
        let t = try await AgentRoomWorktreeService().trace(roomID: room)
        emit(t, json: json) {
            print("ok \(t.ok)")
            print("ledger \(t.ledger.ok ? t.ledger.state : t.ledger.error)")
            print("worktree exists=\(t.worktree.pathExists) git=\(t.worktree.listedByGit) marker=\(t.worktree.markerOK)")
            print("md \(t.documents.filter(\.exists).count)/\(t.documents.count)")
        }
        if !t.ok { exit(1) }
    }

    static func option(_ name: String, _ args: [String]) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        let value = args[idx + 1]
        if value.hasPrefix("-") { return nil }
        return value
    }

    static func requireOccupant(_ args: [String]) -> String {
        if let flag = option("--occupant", args), !flag.isEmpty { return flag }
        if let env = OccupantIdentity.fromEnvironment(), !env.isEmpty { return env }
        FileHandle.standardError.write(
            Data((CLILocalization.string("cli.error.occupant_required") + "\n").utf8)
        )
        exit(64)
    }

    static func requireTenant(_ args: [String]) -> String {
        guard let tenant = option("--tenant", args), !tenant.isEmpty else {
            FileHandle.standardError.write(
                Data((CLILocalization.string("cli.error.tenant_required") + "\n").utf8)
            )
            exit(64)
        }
        return tenant
    }

    static func emit<T: Codable>(_ value: T, json: Bool, human: () -> Void) {
        if json {
            do {
                print(String(data: try Envelope.ok(value), encoding: .utf8) ?? "{}")
            } catch {
                FileHandle.standardError.write(
                    Data((CLILocalization.format("cli.error.open_failed", error.localizedDescription) + "\n").utf8)
                )
                exit(1)
            }
        } else {
            human()
        }
    }

    static func emitFailure(_ error: Error, json: Bool) {
        let message = failureMessage(error)
        guard json else {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return
        }
        emitJSONFailure(message)
    }

    static func failureMessage(_ error: Error) -> String {
        guard let e = error as? AgentRoomWorktreeError else {
            return error.localizedDescription
        }
        switch e {
        case .taskEmpty:
            return CLILocalization.string("cli.error.task_empty")
        case .trivialVerify(let cmd):
            return CLILocalization.format("cli.error.trivial_verify", cmd)
        case .bindNotFound(let id):
            return CLILocalization.format("cli.error.bind_not_found", id)
        case .commandFailed(let d), .worktreeCreateFailed(let d), .spawnRoomFailed(let d):
            return d
        }
    }

    static func emitJSONFailure(_ message: String) {
        let payload = ["ok": false, "error": ["message": message]] as [String: Any]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    }
}
