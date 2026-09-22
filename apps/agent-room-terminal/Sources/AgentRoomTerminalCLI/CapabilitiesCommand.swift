import Foundation
import AppPathsKit
import CommandKit
import InteropKit
import AgentRoomTerminalCore

enum CapabilitiesCommand {
    static func run() {
        let caps = CapabilitiesContract.make(
            cliPath: HostPlatform.cliBinPath(CapabilitiesContract.cliName),
            sqlitePath: DurableAppLayout.tildePath(AppPaths.sqliteFile),
            freshness: "~/.swift-app-state/agent-room-terminal.json"
        )
        guard !caps.depends.isEmpty else {
            CLIIO.fail("depends must be declared")
        }
        CLIIO.printOK(caps)
    }
}

enum VersionCommand {
    static func run() {
        CLIIO.printLine("\(CapabilitiesContract.cliName) \(CapabilitiesContract.version)")
    }
}

enum OpenGUICommand {
    static let hint = "AgentRoomTerminal"

    static func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        let roomID = flagValue(args, flag: "--room")
        let openArgs = makeOpenArgs(hint: hint, roomID: roomID)
        let result = CommandKitSync.run(AppPaths.open, openArgs, timeout: 15)
        guard result.exitCode == 0 else {
            CLIIO.fail(result.stderr.isEmpty ? "open failed" : result.stderr)
        }

        var payload: [String: String] = ["opened": hint]
        if let roomID { payload["room"] = roomID }
        CLIIO.printOKObject(payload)
    }

    private static func makeOpenArgs(hint: String, roomID: String?) -> [String] {
        var openArgs = ["-a", hint]
        if let roomID {
            openArgs += ["--args", "--room", roomID]
        }
        return openArgs
    }

    private static func flagValue(_ args: [String], flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }
}

enum HelpCommand {
    static func run() {
        let cli = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        CLIIO.printLine("""
        \(cli) — room terminal PATH CLI

        \(cli) capabilities [--json]
        \(cli) version
        \(cli) open-gui [--room <room-id>]
        \(cli) open <room-id> [--preset readOnly|toolbelt|open] [--tool <name>] [--successor] [--execute]
        \(cli) open --attach-session <session-id> [--room <room-id>] [--json]
        \(cli) close <room-id> [--execute]
        \(cli) exec <room-id> [--timeout N] -- <command…>
        \(cli) smoke <room-id> --tool <name> [--prompt TEXT]
        \(cli) smoke handoff <room-id> [--execute] [--json]
        \(cli) tree [--tenant T] [--json]
        \(cli) snapshot <room-id> [--lines N]
        \(cli) launch-log <room-id> [--tail N] [--follow]
        \(cli) check --cmd "<command>" [--session <id>] [--tool <name>]
        \(cli) budget <room-id> --json
        \(cli) handoff <room-id> --note "…" [--amend <id>] [--execute]
        \(cli) handoff <room-id> --show <id>
        \(cli) simulate <room-id> --against <bottle-id> --json
        \(cli) habit list|note|promote <room-id> [--candidates|--from-candidates] …
        \(cli) daemon start|stop|status [--json]
        \(cli) usage <room-id> --json
        \(cli) tuning show|set <key> <value>
        \(cli) events <room-id> [--since N] [--follow] [--json]
        \(cli) doctor [--fix] [--json]
        \(cli) profile-lock <room-id> [--trace-file <path>] [--from-candidate] [--apply] [--json]
        \(cli) checkpoint create|rollback|list <room-id> [--id <id>] [--to <id>] [--json]
        \(cli) runs list|show <room-id> [<run-id>] [--json]
        \(cli) precompute <room-id> --targets <paths> --lines <N> --sec <S> [--execute]
        \(cli) delta <room-id> [--break-glass] [--reason <text>] [--execute]
        \(cli) synapses <room-id> [--mask]
        """)
    }
}
