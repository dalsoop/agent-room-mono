import Foundation
import CommandKit
import XCTest
@testable import AgentRoomTerminalCore

final class CLIProcessTests: XCTestCase {
    override func tearDown() {
        DaemonProcessReaper.reapAllTestDaemons()
        super.tearDown()
    }

    func testCapabilitiesEnvelopeFromBinary() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let result = CLITestSupport.runCLI(cli, ["capabilities", "--json"])
        XCTAssertEqual(result.exit, 0, result.stderr)
        let object = try XCTUnwrap(CLITestSupport.json(result.stdout))
        XCTAssertEqual(object["ok"] as? Bool, true)
        let payload = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(payload["name"] as? String, "agent-room-terminal")
        let stateRoot = try XCTUnwrap(payload["stateRoot"] as? [String: Any])
        XCTAssertEqual(stateRoot["env"] as? String, "SWIFT_APP_STATE_ROOT")
    }

    func testCheckFixturesViaBinary() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let pass: [(cmd: String, tool: String?, env: [String: String])] = [
            ("/usr/bin/ls", nil, [:]),
            ("ls", "Agent", [:]),
            ("ls", nil, ["ROOM_ID": "r1"]),
            ("git status", nil, ["ROOM_ID": "r1"]),
            ("cat ROOM.md", nil, ["ROOM_ID": "r1"]),
            ("grep foo", nil, ["ROOM_ID": "r1"]),
        ]
        for item in pass {
            let result = CLITestSupport.runCLI(cli, checkArgs(item.cmd, item.tool), extraEnv: item.env)
            XCTAssertEqual(result.exit, 0, "pass \(item.cmd) stderr=\(result.stderr)")
        }
        let block: [(cmd: String, tool: String?)] = [
            ("/usr/bin/true", nil),
            ("env PATH=/usr/bin ls", nil),
            ("sh -c ls", nil),
            ("bash -c ls", nil),
            ("python3 -c print(1)", nil),
            ("ls", "Agent"),
        ]
        for item in block {
            let result = CLITestSupport.runCLI(
                cli,
                checkArgs(item.cmd, item.tool),
                extraEnv: ["ROOM_ID": "r1"]
            )
            XCTAssertEqual(result.exit, 2, "block \(item.cmd) \(item.tool ?? "")")
        }
    }

    func testDryRunOpenCloseHandoffPromote() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("art-dry-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let env = CLITestSupport.openEnv(root: root)
        try CLITestSupport.writeFixtureCLIs(root: root)
        let room = CLITestSupport.roomID
        for argv in [
            ["open", room],
            ["close", room],
            ["handoff", room, "--note", "later"],
            ["habit", "promote", room, "1"],
        ] {
            let result = CLITestSupport.runCLI(cli, argv, extraEnv: env)
            XCTAssertEqual(result.exit, 0, "\(argv) \(result.stderr) \(result.stdout)")
            let object = try XCTUnwrap(CLITestSupport.json(result.stdout))
            let payload = try XCTUnwrap(object["result"] as? [String: Any])
            XCTAssertEqual(payload["dryRun"] as? Bool, true, argv.joined(separator: " "))
            XCTAssertEqual(payload["executed"] as? Bool, false)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.log").path)
        )
    }

    func testTuningRoundTripViaBinary() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("art-tune-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let env = ["SWIFT_APP_STATE_ROOT": root.path]
        let set = CLITestSupport.runCLI(cli, ["tuning", "set", "idleSeconds", "77"], extraEnv: env)
        XCTAssertEqual(set.exit, 0, set.stderr)
        let show = CLITestSupport.runCLI(cli, ["tuning", "show"], extraEnv: env)
        XCTAssertEqual(show.exit, 0, show.stderr)
        let payload = try XCTUnwrap(CLITestSupport.json(show.stdout)?["result"] as? [String: Any])
        XCTAssertEqual(payload["idleSeconds"] as? Double, 77)
    }

    private static func canApplySandboxExec() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)", "/usr/bin/true"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func testRuntimeSmoke() throws {
        guard Self.canApplySandboxExec() else {
            throw XCTSkip("sandbox-exec not permitted in current environment")
        }
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let daemon = try XCTUnwrap(CLITestSupport.product("agent-room-terminal-daemon"))
        XCTAssertEqual(cli.deletingLastPathComponent().path, daemon.deletingLastPathComponent().path)
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("art-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try CLITestSupport.writeFixtureCLIs(root: root)
        var env = CLITestSupport.openEnv(root: root)
        env["AGENT_ROOM_TERMINAL_DAEMON"] = daemon.path
        let cleanupEnv = env
        addTeardownBlock {
            _ = CLITestSupport.runCLI(cli, ["daemon", "stop", "--json"], extraEnv: cleanupEnv)
            DaemonProcessReaper.reapDaemons(root: root)
            try? FileManager.default.removeItem(at: root)
        }
        let start = CLITestSupport.runCLI(cli, ["daemon", "start", "--json"], extraEnv: env)
        XCTAssertEqual(start.exit, 0, start.stderr + start.stdout)
        let room = CLITestSupport.roomID
        let opened = CLITestSupport.runCLI(cli, ["open", room, "--execute"], extraEnv: env)
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let exec = CLITestSupport.runCLI(cli, ["exec", room, "--", "ls"], extraEnv: env)
        XCTAssertEqual(exec.exit, 0, exec.stderr + exec.stdout)
        let closed = CLITestSupport.runCLI(cli, ["close", room, "--execute"], extraEnv: env)
        XCTAssertEqual(closed.exit, 0, closed.stderr + closed.stdout)
        let stopped = CLITestSupport.runCLI(cli, ["daemon", "stop", "--json"], extraEnv: env)
        XCTAssertEqual(stopped.exit, 0, stopped.stderr + stopped.stdout)
    }

    func testCommandKitDrains300KB() {
        let script = "import sys; sys.stdout.write('x' * 300000)"
        let result = CommandKitSync.run("/usr/bin/python3", ["-c", script], timeout: 10)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertGreaterThanOrEqual(result.stdout.utf8.count, 300_000)
    }

    private func checkArgs(_ command: String, _ tool: String?) -> [String] {
        var args = ["check", "--cmd", command]
        if let tool {
            args += ["--tool", tool]
        }
        return args
    }

}
