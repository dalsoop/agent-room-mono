import SingleInstanceKit
import Foundation
import AgentCLIKit
import os
import InteropKit
import AppScaffoldKit
import AppPathsKit
import AgentRoomMonitorCore
import LocalizationKit

SingleInstanceCLI.autoGuard()

// Cloud Apps 게이트 — GUI 의 `.gujoManaged()` 와 대칭인 CLI 진입 한 줄.
// import 직후라 **무엇보다 먼저** 돈다. help·version·capabilities 와 판정 실패는 통과한다
// (절차: swiftkit-appscaffold/Documentation/gujo-managed.md). 동기 판이다 — await 를 넣으면
// 이 파일이 async 컨텍스트가 되고 Thread.sleep 같은 noasync API 를 쓰던 앱이 컴파일에서 죽는다.
GujoManaged.exitIfNotEntitledSync()

// agent-room-monitor — dual-entry Helpers CLI (Foundation only).
// PATH must never point at .app/Contents/MacOS GUI (dual-entry hang 2026-07-25).
// Extend with real subcommands; keep AppKit out of this target.

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"

/// async 코드를 top-level 스크립트(non-async 컨텍스트)에서 블로킹 호출한다.
/// 이 파일 전체를 async 로 만들면 Thread.sleep 등 noasync API 사용부가 깨진다.
func runSync<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let sema = DispatchSemaphore(value: 0)
    let box = LockedBox<T>()
    Task {
        let result = await body()
        box.value = result
        sema.signal()
    }
    sema.wait()
    guard let value = box.value else {
        preconditionFailure("runSync finished without value")
    }
    return value
}

final class LockedBox<T>: @unchecked Sendable {
    var value: T?
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) else {
        print("{}")
        return
    }
    print(s)
}

struct StatusSummary: Codable {
    var rooms: Int
    var executing: Int
    var blocked: Int
    var gates: Int
    var skills: Int
    var sessions: Int
}

func firstNode(_ node: TwinNode, id: String) -> TwinNode? {
    if node.id == id { return node }
    for child in node.children {
        if let hit = firstNode(child, id: id) { return hit }
    }
    return nil
}

struct StateCounts: Equatable {
    var rooms = 0
    var executing = 0
    var blocked = 0
    var gates = 0
}

func countStates(_ node: TwinNode) -> StateCounts {
    var counts = StateCounts()
    if node.icon == "🚪" {
        counts.rooms += 1
        switch node.state {
        case .exec: counts.executing += 1
        case .block: counts.blocked += 1
        case .gate: counts.gates += 1
        default: break
        }
    }
    for child in node.children {
        let sub = countStates(child)
        counts.rooms += sub.rooms
        counts.executing += sub.executing
        counts.blocked += sub.blocked
        counts.gates += sub.gates
    }
    return counts
}

private func flagValue(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func repeatedFlags(_ flag: String, in args: [String]) -> [String] {
    var out: [String] = []
    var i = 0
    while i + 1 < args.count {
        guard args[i] == flag else {
            i += 1
            continue
        }
        out.append(args[i + 1])
        i += 1
    }
    return out
}

func usage() {
    print(
        """
        agent-room-monitor — AgentRoomMonitor CLI (helpers dual-entry)

        Commands:
          capabilities              앱 상호운용 계약({ok,result} 봉투) 출력
          snapshot --json           TwinSnapshot 전체(방·자리·스킬·세션·텔레메트리) 출력
          status --json             요약(rooms/executing/blocked/gates/skills/sessions)
          telemetry --json          호스트 텔레메트리만 출력
          views --json              뷰 정의(~/.agent-room-monitor/views/*.json) 목록 — 없으면 기본 시드
          compare --json            최근 두 스냅샷 diff (생긴/사라진/상태 변경)
          trace [--room ID] --json  방 단위 시점 이벤트
          mutate spawn-room --task T --verify V --handle N --tenant ID --occupant A --workdir PATH [--tool CLI]* [--write GLOB]*
          mutate occupy <plan> <room> --occupant agent:tool@host
          mutate tick <plan> [--workdir PATH]
          mutate demolish <blueprint-slug>
          mutate reject <plan>
          mutate handoff-pack <session-id>
          mutate handoff-resume <session-id> --to claude|codex|grok
          mutate open-skill <name>
          mutate seal <room-id> [--tenant ID] [--enforce-drain]
          mutate archive <room-id> [--tenant ID]
          mutate promote-skill <room-id> --skill NAME [--tenant ID] [--target-dir PATH] [--scope tenant|global] [--force] [--auto-bump]
          mutate search-memory --query TEXT [--tenant ID]
          ax --app <name> --json    점유 앱 AX 트리 요약
          version, -V, --version    Print CLI stamp
          help, -h, --help          This help
          open                      Open the GUI app (via /usr/bin/open)

        다음 할 일(계약·ship·MR 절차): agent-cli-scaffold checklist --app agent-room-monitor

        Install after the feature MR is merged:
          app-build-manager ship apps/<app> release
        """
    )
}


func runAgentCLI(_ cliArgs: [String]) -> Never {
    let state = OSAllocatedUnfairLock(initialState: (code: Int32(0), done: false))
    let app = AgentCLIApp(
        slug: "agent-room-monitor",
        workspaceRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        domainContext: { "agent-room-monitor app" }
    )
    let cli = AgentCLICommand(app: app)
    Task {
        let result = await cli.handle(cliArgs)
        if case .handled(let c) = result { state.withLock { $0.code = c } }
        else { state.withLock { $0.code = 64 } }
        state.withLock { $0.done = true }
    }
    while !state.withLock({ $0.done }) {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    exit(state.withLock { $0.code })
}

switch cmd {
    case "agent", "skill", "chat":
        runAgentCLI(Array(CommandLine.arguments.dropFirst()))

case "help", "-h", "--help":
    usage()
case "version", "-V", "--version":
    CLIMarketingVersion.printLine(name: "agent-room-monitor")
case "capabilities":
    let caps = InteropKit.Capabilities(
        name: "agent-room-monitor",
        cli: HostPlatform.cliBinPath("agent-room-monitor"),
        commands: [
            .init(name: "capabilities", summary: CLILocalization.string("main.string"), json: true),
            .init(name: "snapshot", summary: CLILocalization.string("main.string-2"), json: true),
            .init(name: "status", summary: CLILocalization.string("main.string-3"), json: true),
            .init(name: "telemetry", summary: CLILocalization.string("main.string-4"), json: true),
            .init(name: "views", summary: CLILocalization.string("main.string-5"), json: true),
            .init(name: "compare", summary: CLILocalization.string("main.string-6"), json: true),
            .init(name: "trace", summary: CLILocalization.string("main.string-7"), json: true),
            .init(name: "mutate", summary: CLILocalization.string("main.string-8"), json: true),
            .init(name: "ax", summary: CLILocalization.string("main.string-9"), json: true),
            .init(name: "version", summary: CLILocalization.string("main.string-10"), json: false),
            .init(name: "open", summary: CLILocalization.string("main.string-11"), json: false),
            .init(name: "help", summary: "도움말 출력", json: false),
            .init(name: "agent", summary: "실행 중 에이전트 조회", json: false),
            .init(name: "skill", summary: "워크스페이스 스킬 조회", json: false),
            .init(name: "chat", summary: "이 앱 맥락으로 에이전트에 질의", json: false),
        ],
        state: [
            .init(
                path: DurableAppLayout.tildePath(DurableAppLayout.sqliteURL(slug: "agent-room-monitor")),
                what: CLILocalization.string("main.string-12")
            ),
            .init(
                path: "~/.swift-app-state/agent-room-monitor.json",
                what: CLILocalization.string("main.string-13")
            ),
        ],
        health: .init(
            command: "\(HostPlatform.cliBinPath("agent-room-monitor")) capabilities",
            freshness: "~/.swift-app-state/agent-room-monitor.json"
        ),
        // 예: .init(id: "system.git", kind: Capabilities.DependencyKind.command,
        //          ref: "git", required: true, why: "…")
        // monorepo 타 CLI 면 kind: cli + commands, 같은 계약을 interop-expects.json 에도.
        depends: []
    )
    let data = try Envelope.ok(caps)
    print(String(data: data, encoding: .utf8) ?? "{}")
case "snapshot":
    let snapshot = runSync { await SnapshotBuilder().build() }
    printJSON(snapshot)
    StateMirrorAdoption.publish(snapshot: snapshot)
case "status":
    let snapshot = runSync { await SnapshotBuilder().build() }
    let agg = countStates(snapshot.root)
    let warehouse = firstNode(snapshot.root, id: "skill-warehouse")
    let skills = warehouse?.children.reduce(0) { $0 + $1.children.count } ?? 0
    let sessionCards = firstNode(snapshot.root, id: "sessions")?.children.count ?? 0
    let summary = StatusSummary(
        rooms: agg.rooms,
        executing: agg.executing,
        blocked: agg.blocked,
        gates: agg.gates,
        skills: skills,
        sessions: sessionCards
    )
    printJSON(summary)
    StateMirrorAdoption.publish(snapshot: snapshot)
case "views":
    printJSON(ViewSpecStore().loadOrSeed())
case "telemetry":
    let snapshot = runSync { await SnapshotBuilder().build() }
    printJSON(snapshot.telemetry)
case "compare":
    let snapshot = runSync { await SnapshotBuilder().build() }
    do {
        try SnapshotArchive().record(snapshot)
    } catch {
        fputs("warning: snapshot archive record failed: \(error)\n", stderr)
    }
    if let pair = SnapshotArchive().latestPair() {
        printJSON(SnapshotDiffing.diff(old: pair.older.root, new: pair.newer.root))
    } else {
        printJSON(SnapshotDiff())
    }
    StateMirrorAdoption.publish(snapshot: snapshot)
case "trace":
    let roomFlag = args.dropFirst().firstIndex(of: "--room")
    var roomID: String?
    if let idx = roomFlag {
        let rest = Array(args.dropFirst())
        let i = rest.distance(from: rest.startIndex, to: idx)
        if i + 1 < rest.count { roomID = rest[i + 1] }
    }
    let snapshot = runSync { await SnapshotBuilder().build() }
    let events: [TraceEvent]
    if let roomID {
        events = snapshot.trace.filter { $0.roomID == nil || $0.roomID == roomID }
    } else {
        events = snapshot.trace
    }
    printJSON(events)
case "ax":
    var appName = "AgentRoomMonitor"
    let rest = Array(args.dropFirst())
    if let i = rest.firstIndex(of: "--app"), i + 1 < rest.count {
        appName = rest[i + 1]
    }
    let targetApp = appName
    let result = runSync { await OccupancyAX().see(appName: targetApp) }
    printJSON(["ok": result.ok ? "true" : "false", "app": result.appName, "text": result.text])
case "mutate":
    let rest = Array(args.dropFirst())
    var mutation: RoomMutation?
    switch rest.first {
    case "spawn-room":
        guard let task = flagValue("--task", in: rest),
              let verify = flagValue("--verify", in: rest),
              let handle = flagValue("--handle", in: rest) else {
            mutation = nil; break
        }
        guard let occupant = flagValue("--occupant", in: rest),
              let tenant = flagValue("--tenant", in: rest) else {
            mutation = nil; break
        }
        mutation = .spawnRoom(
            task: task, verify: verify, handle: handle,
            occupant: occupant,
            workdir: flagValue("--workdir", in: rest) ?? FileManager.default.currentDirectoryPath,
            tenant: tenant,
            tools: repeatedFlags("--tool", in: rest),
            writes: repeatedFlags("--write", in: rest)
        )
    case "occupy":
        guard rest.count >= 3 else { mutation = nil; break }
        guard let occIdx = rest.firstIndex(of: "--occupant"), occIdx + 1 < rest.count else {
            mutation = nil; break
        }
        mutation = .occupy(planID: rest[1], roomID: rest[2], occupant: rest[occIdx + 1])
    case "tick":
        guard rest.count >= 2 else { mutation = nil; break }
        let planID = rest[1]
        var workdir: String?
        if let wdIdx = rest.firstIndex(of: "--workdir"), wdIdx + 1 < rest.count {
            workdir = rest[wdIdx + 1]
        }
        mutation = .tick(planID: planID, workdir: workdir)
    case "demolish":
        guard rest.count >= 2 else { mutation = nil; break }
        mutation = .demolishBlueprint(slug: rest[1])
    case "reject":
        guard rest.count >= 2 else { mutation = nil; break }
        mutation = .rejectPlacement(planID: rest[1], by: "agent-room-monitor")
    case "handoff-pack":
        guard rest.count >= 2 else { mutation = nil; break }
        mutation = .handoffPack(sessionID: rest[1])
    case "handoff-resume":
        guard rest.count >= 2 else { mutation = nil; break }
        guard let toIdx = rest.firstIndex(of: "--to"), toIdx + 1 < rest.count else {
            mutation = nil; break
        }
        let to = rest[toIdx + 1]
        mutation = .handoffResume(sessionID: rest[1], to: to)
    case "open-skill":
        guard rest.count >= 2 else { mutation = nil; break }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/skills", isDirectory: true)
        mutation = .openSkill(name: rest[1], skillsDir: dir)
    case "seal":
        guard rest.count >= 2 else { mutation = nil; break }
        let roomID = rest[1]
        let tenant = flagValue("--tenant", in: rest) ?? "default"
        let drain = rest.contains("--enforce-drain")
        mutation = .sealRoom(roomID: roomID, tenant: tenant, enforceDrain: drain)
    case "archive":
        guard rest.count >= 2 else { mutation = nil; break }
        let roomID = rest[1]
        let tenant = flagValue("--tenant", in: rest) ?? "default"
        mutation = .archiveRoom(roomID: roomID, tenant: tenant)
    case "promote-skill":
        guard rest.count >= 2, let skillName = flagValue("--skill", in: rest) else { mutation = nil; break }
        let roomID = rest[1]
        let tenant = flagValue("--tenant", in: rest) ?? "default"
        let targetDir = flagValue("--target-dir", in: rest)
        let scope = flagValue("--scope", in: rest) ?? "tenant"
        let force = rest.contains("--force")
        let autoBump = rest.contains("--auto-bump")
        mutation = .promoteSkill(
            roomID: roomID,
            tenant: tenant,
            skillName: skillName,
            targetDir: targetDir,
            scope: scope,
            force: force,
            autoBump: autoBump
        )
    case "search-memory":
        guard let query = flagValue("--query", in: rest) else { mutation = nil; break }
        let tenant = flagValue("--tenant", in: rest) ?? "default"
        mutation = .searchMemory(tenant: tenant, query: query)
    default:
        mutation = nil
    }
    guard let mutation else {
        let msg = "usage: mutate spawn-room|occupy|tick|demolish|reject|"
            + "handoff-pack|handoff-resume|open-skill|seal|archive|promote-skill|search-memory …\n"
        FileHandle.standardError.write(Data(msg.utf8))
        exit(64)
    }
    let action = mutation
    let result = runSync { await RoomMutationService().perform(action) }
    printJSON(result)
    if !result.ok { exit(1) }
case "open":
    let appURL = URL(fileURLWithPath: "/Applications/AgentRoomMonitor.app")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if FileManager.default.fileExists(atPath: appURL.path) {
        p.arguments = [appURL.path]
    } else {
        p.arguments = ["-a", "AgentRoomMonitor"]
    }
    do {
        try p.run()
    } catch {
        FileHandle.standardError.write(Data("error: open failed: \(error)\n".utf8))
        exit(1)
    }
default:
    FileHandle.standardError.write(Data("unknown command: \(cmd) (try help)\n".utf8))
    usage()
    exit(64)
}
