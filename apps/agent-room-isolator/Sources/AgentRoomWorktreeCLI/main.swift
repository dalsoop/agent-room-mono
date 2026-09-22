import SingleInstanceKit
import Foundation
import InteropKit
import AppScaffoldKit
import AppPathsKit
import LocalizationKit
import AgentCLIKit
import AgentRoomWorktreeCore
import CommandKit

SingleInstanceCLI.autoGuard()

// Cloud Apps 게이트 — GUI 의 `.gujoManaged()` 와 대칭인 CLI 진입 한 줄.
// 모듈 로드 직후라 **무엇보다 먼저** 돈다. help·version·capabilities 와 판정 실패는 통과한다
// (절차: swiftkit-appscaffold/Documentation/gujo-managed.md). 동기 판이다 — await 를 넣으면
// 이 파일이 async 컨텍스트가 되고 Thread.sleep 같은 noasync API 를 쓰던 앱이 컴파일에서 죽는다.
GujoManaged.exitIfNotEntitledSync()

// agent-room-worktree — dual-entry Helpers CLI (Foundation + LocalizationKit).
// PATH must never point at .app/Contents/MacOS GUI (dual-entry hang 2026-07-25).
// Extend with real subcommands; keep AppKit out of this target.
//
// 출력 문자열 i18n — app-i18n-inspector CLI 축(cli-*)이 잡는 결함 클래스:
// - 사람이 읽는 출력(usage·오류)은 CLILocalization 으로 라우팅한다. 번들은 설치본에서
//   .app/Contents/Resources 의 앱 테이블을 공유한다(CLILocalization doc 참조).
// - 기계가 읽는 capabilities JSON 의 summary 는 영어 고정 — 계약 소비자가 언어와
//   무관하게 안정적으로 읽어야 한다.
// - 오류 보간은 `\(error)`Raw 가 아니라 error.localizedDescription.

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"

func usage() {
    print(CLILocalization.string("cli.usage"))
    // 실행 가능한 예시(help-example 계약) — argv0 이 곧 CLI 이름이라 설치 어디서든
    // 그대로 복사해 실행되는 줄이 나온다.
    let cliName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    print("""
    \(cliName) capabilities --json
    \(cliName) provision --task "…" --verify "…" --repo PATH --occupant HANDLE --tenant TENANT --dry-run --json
    \(cliName) trace --room UUID --json
    """)
}

switch cmd {
case "help", "-h", "--help":
    usage()
case "version", "-V", "--version":
    CLIMarketingVersion.printLine(name: "agent-room-worktree")
case "capabilities":
    // 앱 상호운용 계약(docs/app-interop-contract.md) — 소비자가 호출 표면을 기계적으로 읽는다.
    // Domain commands are listed below; runtime siblings go in depends (not USAGE/README).
    let caps = InteropKit.Capabilities(
        name: "agent-room-worktree",
        cli: HostPlatform.cliBinPath("agent-room-worktree"),
        commands: [
            .init(name: "capabilities", summary: "print this interop contract", json: true),
            .init(name: "help", summary: "print usage", json: false),
            .init(name: "version", summary: "print CLI stamp", json: false),
            .init(name: "open", summary: "open the GUI app", json: false),
            .init(name: "status", summary: "print bind count", json: true),
            .init(name: "provision", summary: "validate room concept, create git worktree, bind, emit MD", json: true),
            .init(name: "bind", summary: "record roomID ↔ worktree path", json: true),
            .init(name: "emit-md", summary: "write ROOM.md DESIGN.md AGENTS.md into the room folder", json: true),
            .init(name: "list", summary: "list room ↔ worktree binds", json: true),
            .init(name: "show", summary: "show one bind", json: true),
            .init(name: "trace", summary: "bind + ledger + git worktree + MD in one record", json: true),
            .init(name: "doctor", summary: "check binds, ledger, git worktrees, and room MD files", json: true),
        ],
        state: [
            // 경로는 Core/AppPaths 가 StateRootKit 루트 아래로 조립한다 — 테넌트 컨텍스트면
            // ~/.tenants/<t>/ 아래가 그대로 찍힌다. CLI 가 홈을 따로 조립하지 않는다.
            .init(
                path: DurableAppLayout.tildePath(RoomWorktreePaths.sqliteFile),
                what: "settings & work sqlite app.sqlite (source of truth; under the StateRootKit root)"
            ),
            .init(
                path: "~/.swift-app-state/agent-room-worktree.json",
                what: "app state summary (StateMirrorAdoption — observability mirror, not the source)"
            ),
        ],
        health: .init(
            command: "\(HostPlatform.cliBinPath("agent-room-worktree")) status",
            freshness: "~/.swift-app-state/agent-room-worktree.json"
        ),
        // 예: .init(id: "system.git", kind: Capabilities.DependencyKind.command,
        //          ref: "git", required: true, why: "…")
        // monorepo 타 CLI 면 kind: cli + commands, 같은 계약을 interop-expects.json 에도.
        depends: [
            .init(
                id: "cli.agent-work-todo",
                kind: Capabilities.DependencyKind.cli,
                ref: "agent-work-todo",
                required: true,
                why: "room ledger: spawn-room --waiting --workdir"
            ),
            .init(
                id: "cli.agent-worktree-control-terminal",
                kind: Capabilities.DependencyKind.cli,
                ref: "agent-worktree-control-terminal",
                required: true,
                why: "git worktree create --inside; this app does not call git worktree"
            ),
        ]
    )
    let data = try Envelope.ok(caps)
    print(String(data: data, encoding: .utf8) ?? "{}")
case "open":
    let hint = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    let safeResult = SafeProcessRunner.run(
        "/usr/bin/open",
        ["-a", hint]
    )
    } catch {
        FileHandle.standardError.write(
            Data((CLILocalization.format("cli.error.open_failed", error.localizedDescription) + "\n").utf8)
        )
        exit(1)
    }
case "status", "provision", "bind", "emit-md", "list", "show", "doctor", "trace":
    let rest = Array(args.dropFirst())
    runDomain(cmd, rest)
default:
    FileHandle.standardError.write(
        Data((CLILocalization.format("cli.error.unknown_command", cmd) + "\n").utf8)
    )
    usage()
    exit(64)
}

/// Wait for async domain commands from a sync Helpers entry. CFRunLoop avoids DispatchSemaphore + Task.
func runDomain(_ cmd: String, _ rest: [String]) {
    let loop = CFRunLoopGetCurrent()
    Task {
        await DomainCommands.run(cmd, rest)
        CFRunLoopStop(loop)
    }
    CFRunLoopRun()
}
