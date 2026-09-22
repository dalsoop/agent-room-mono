import Foundation
import CommandKit
import InteropKit
import RoomKit
import StateRootKit

/// 조작 = 실행 (요구사항 A.3). 화면 버튼은 소유 앱 CLI 만 호출한다.
/// 방 철거 → `agent-work-todo room rm` / 심사 반려
/// 에이전트 입주 → `placement occupy`
/// 핸드오프 → `agent-handoff pack` · `resume`
/// 스킬 카드 편집 → SKILL.md 를 `open`
public enum RoomMutation: Sendable, Equatable {
    case occupy(planID: String, roomID: String, occupant: String)
    case tick(planID: String, workdir: String? = nil)
    case gate(planID: String, roomID: String, by: String, reject: Bool)
    case demolishBlueprint(slug: String)
    case rejectPlacement(planID: String, by: String)
    case handoffPack(sessionID: String)
    case handoffResume(sessionID: String, to: String)
    case openSkill(name: String, skillsDir: URL)
    /// 스킬을 방 설계도 toolbelt에 붙인다. `room toolbelt-add`.
    case attachSkill(slug: String, tool: String)
    /// 방 생성 = 도메인 할당. 소유 CLI `placement spawn-room`.
    case spawnRoom(
        task: String,
        verify: String,
        handle: String,
        occupant: String,
        workdir: String,
        tenant: String,
        tools: [String],
        writes: [String]
    )
    /// 룸 볼트 봉인 (스냅샷 생성 및 동결)
    case sealRoom(roomID: String, tenant: String, enforceDrain: Bool)
    /// 룸 볼트 아카이브 (raw 디렉토리 정리 및 콜드 보존)
    case archiveRoom(roomID: String, tenant: String)
    /// 룸 로컬 스킬을 상위(테넌트/전역)로 승격
    case promoteSkill(
        roomID: String,
        tenant: String,
        skillName: String,
        targetDir: String?,
        scope: String,
        force: Bool,
        autoBump: Bool = false
    )
    /// 룸 볼트 교차 메모리 검색
    case searchMemory(tenant: String, query: String)

    public var timeout: TimeInterval {
        switch self {
        case .tick:
            return 180.0
        case .spawnRoom:
            return 120.0
        default:
            return 30.0
        }
    }
}

public struct RoomMutationResult: Sendable, Equatable, Codable {
    public var ok: Bool
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(ok: Bool, command: String, stdout: String, stderr: String, exitCode: Int32) {
        self.ok = ok
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public struct RoomMutationService: Sendable {
    private let runner: CommandRunning
    private let workTodo: String
    private let handoff: String
    private let openBin: String

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        workTodo: String = HostPlatform.cliBinPath("agent-work-todo"),
        handoff: String = HostPlatform.cliBinPath("agent-handoff"),
        openBin: String = "/usr/bin/open"
    ) {
        self.runner = runner
        self.workTodo = workTodo
        self.handoff = handoff
        self.openBin = openBin
    }

    public func perform(_ mutation: RoomMutation) async -> RoomMutationResult {
        switch mutation {
        case let .sealRoom(roomID, tenant, enforceDrain):
            return performSeal(roomID: roomID, tenant: tenant, enforceDrain: enforceDrain)
        case let .archiveRoom(roomID, tenant):
            return performArchive(roomID: roomID, tenant: tenant)
        case let .promoteSkill(roomID, tenant, skillName, targetDir, scope, force, autoBump):
            return performPromote(
                roomID: roomID,
                tenant: tenant,
                skillName: skillName,
                targetDir: targetDir,
                scope: scope,
                force: force,
                autoBump: autoBump
            )
        case let .searchMemory(tenant, query):
            return performSearchMemory(tenant: tenant, query: query)
        case let .spawnRoom(_, _, handle, _, _, tenant, _, _):
            if let reason = RoomHandleGate.reason(handle) {
                return RoomMutationResult(
                    ok: false, command: "placement spawn-room",
                    stdout: "", stderr: "이름 게이트: \(reason)", exitCode: 64)
            }
            let layout = RoomVaultLayout.forRoom(tenant: tenant, roomID: handle)
            do {
                try RoomVaultManager().ensureLayout(at: layout)
            } catch {
                fputs("warning: pre-initializing room layout failed: \(error)\n", stderr)
            }
        default:
            break
        }

        let inv = argv(mutation)
        let result = await runner.run(inv.path, inv.args, timeout: mutation.timeout)
        return RoomMutationResult(
            ok: result.ok,
            command: ([inv.path] + inv.args).joined(separator: " "),
            stdout: result.trimmedStdout,
            stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: result.exitCode
        )
    }

    private func performSeal(roomID: String, tenant: String, enforceDrain: Bool) -> RoomMutationResult {
        let layout = RoomVaultLayout.forRoom(tenant: tenant, roomID: roomID)
        let archiver = RoomLifecycleArchiver()
        do {
            let sealed = try archiver.seal(
                roomID: roomID,
                tenant: tenant,
                layout: layout,
                enforceDrain: enforceDrain
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = (try? encoder.encode(sealed)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return RoomMutationResult(ok: true, command: "mutate seal \(roomID)", stdout: json, stderr: "", exitCode: 0)
        } catch {
            return RoomMutationResult(ok: false, command: "mutate seal \(roomID)", stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    private func performArchive(roomID: String, tenant: String) -> RoomMutationResult {
        let layout = RoomVaultLayout.forRoom(tenant: tenant, roomID: roomID)
        let archiver = RoomLifecycleArchiver()
        do {
            let archived = try archiver.archive(layout: layout)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = (try? encoder.encode(archived)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return RoomMutationResult(ok: true, command: "mutate archive \(roomID)", stdout: json, stderr: "", exitCode: 0)
        } catch {
            return RoomMutationResult(ok: false, command: "mutate archive \(roomID)", stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    private func performPromote(
        roomID: String,
        tenant: String,
        skillName: String,
        targetDir: String?,
        scope: String,
        force: Bool,
        autoBump: Bool
    ) -> RoomMutationResult {
        let layout = RoomVaultLayout.forRoom(tenant: tenant, roomID: roomID)
        let targetURL = resolveTargetURL(targetDir: targetDir, tenant: tenant, scope: scope)
        let promotionScope = resolvePromotionScope(tenant: tenant, scope: scope)
        let policy: PromotionConflictPolicy = autoBump ? .autoBump : (force ? .force : .reject)

        let gate = RoomPromotionGate()
        do {
            let receipt = try gate.promote(
                skillName: skillName,
                roomID: roomID,
                tenant: tenant,
                in: layout,
                targetDirectory: targetURL,
                scope: promotionScope,
                forceMerge: force,
                conflictPolicy: policy
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = (try? encoder.encode(receipt)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return RoomMutationResult(ok: true, command: "mutate promote-skill \(roomID)", stdout: json, stderr: "", exitCode: 0)
        } catch {
            return RoomMutationResult(ok: false, command: "mutate promote-skill \(roomID)", stdout: "", stderr: "\(error)", exitCode: 1)
        }
    }

    private func performSearchMemory(tenant: String, query: String) -> RoomMutationResult {
        let indexer = RoomMemoryIndexer()
        let results = indexer.search(query: query, tenant: tenant)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(results)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return RoomMutationResult(ok: true, command: "mutate search-memory", stdout: json, stderr: "", exitCode: 0)
    }

    private func resolveTargetURL(targetDir: String?, tenant: String, scope: String) -> URL {
        guard let targetDir else {
            if scope == "global" {
                return StateRootKit.url(".codex/skills")
            }
            let tenantRoot = StateRootKit.tenantStateRoot(tenant: tenant)
            return URL(fileURLWithPath: tenantRoot).appendingPathComponent("skills", isDirectory: true)
        }
        return URL(fileURLWithPath: targetDir)
    }

    private func resolvePromotionScope(tenant: String, scope: String) -> PromotionScope {
        if scope == "global" {
            return .global
        }
        return .tenant(tenant)
    }

    private struct Invocation {
        let path: String
        let args: [String]
    }

    private func argv(_ mutation: RoomMutation) -> Invocation {
        switch mutation {
        case let .occupy(planID, roomID, occupant):
            return Invocation(path: workTodo, args: ["placement", "occupy", planID, roomID, "--occupant", occupant])
        case let .tick(planID, workdir):
            var args = ["placement", "tick", planID]
            if let wd = workdir, !wd.isEmpty { args += ["--workdir", wd] }
            return Invocation(path: workTodo, args: args)
        case let .gate(planID, roomID, by, reject):
            var args = ["placement", "gate", planID, roomID, "--by", by]
            if reject { args.append("--reject") }
            return Invocation(path: workTodo, args: args)
        case let .demolishBlueprint(slug):
            return Invocation(path: workTodo, args: ["room", "rm", slug])
        case let .rejectPlacement(planID, by):
            return Invocation(
                path: workTodo,
                args: ["placement", "reject", planID, "--by", by, "--reason", "room-monitor demolish", "--json"]
            )
        case let .handoffPack(sessionID):
            return Invocation(path: handoff, args: ["pack", sessionID, "--json"])
        case let .handoffResume(sessionID, to):
            return Invocation(path: handoff, args: ["resume", sessionID, "--to", to, "--json"])
        case let .openSkill(name, skillsDir):
            let skillMD = skillsDir.appendingPathComponent(name).appendingPathComponent("SKILL.md")
            return Invocation(path: openBin, args: [skillMD.path])
        case let .attachSkill(slug, tool):
            return Invocation(path: workTodo, args: ["room", "toolbelt-add", slug, "--tool", tool])
        case let .spawnRoom(task, verify, handle, occupant, workdir, tenant, tools, writes):
            return spawnRoomArgv(
                task: task, verify: verify, handle: handle,
                occupant: occupant, workdir: workdir, tenant: tenant,
                tools: tools, writes: writes
            )
        default:
            return Invocation(path: "/usr/bin/true", args: [])
        }
    }

    private func spawnRoomArgv(
        task: String, verify: String, handle: String, occupant: String,
        workdir: String, tenant: String, tools: [String], writes: [String]
    ) -> Invocation {
        var args = [
            "placement", "spawn-room",
            "--task", task, "--verify", verify, "--handle", handle,
            "--occupant", occupant, "--workdir", workdir, "--tenant", tenant,
            "--via", "agent-room-monitor"
        ]
        for tool in tools { args += ["--tool", tool] }
        for glob in writes { args += ["--write", glob] }
        return Invocation(path: workTodo, args: args)
    }
}
