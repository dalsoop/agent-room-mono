import Foundation
import XCTest
import CommandKit
import RoomKit
@testable import AgentRoomTerminalCore

struct SmokeHarness {
    static let defaultRoomID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    static let defaultPlanID = "550e8400-e29b-41d4-a716-446655440000"

    var root: URL
    var cli: URL
    var daemon: URL
    var argvLogURL: URL
    var envPairs: [String]
    var roomID: String
    var planID: String

    var argvLogText: String {
        (try? String(contentsOf: argvLogURL, encoding: .utf8)) ?? ""
    }

    var argvLog: [String] {
        argvLogText.split(whereSeparator: \.isNewline).map(String.init)
    }

    static func make(
        roomID: String = defaultRoomID,
        planID: String = defaultPlanID
    ) throws -> SmokeHarness {
        let cli = try locate("agent-room-terminal")
        let daemon = try locate("agent-room-terminal-daemon")
        let fm = FileManager.default
        // Unix socket path cap is ~104 bytes on macOS — keep the temp root short.
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("art-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let argvLog = root.appendingPathComponent("ledger-argv.log")
        try Data().write(to: argvLog)
        let pad = root.appendingPathComponent("pad.txt")
        try String(repeating: "x", count: 300_000).write(to: pad, atomically: true, encoding: .utf8)
        try writeStubs(bin: bin, argvLog: argvLog, pad: pad, roomID: roomID, planID: planID)
        let path = [bin.path, "/usr/bin", "/bin", "/usr/local/bin"].joined(separator: ":")
        let roomFolder = root
            .appendingPathComponent(".tenants", isDirectory: true)
            .appendingPathComponent("gujo", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent(roomID, isDirectory: true)
        try fm.createDirectory(at: roomFolder, withIntermediateDirectories: true)
        let spec = RoomSpec(
            roomID: UUID(uuidString: roomID) ?? UUID(),
            tenant: "tenant:gujo",
            task: "smoke test",
            verdict: "true",
            walls: RoomWalls(
                filesystem: FilesystemWall(allowWrite: []),
                network: .open
            ),
            launch: RoomLaunch(tool: .claude),
            executionPolicy: RoomExecutionPolicy(
                lineage: RoomLineage(planID: planID, blueprintSlug: "smoke-room"),
                budget: .zero
            )
        )
        let specData = try JSONEncoder().encode(spec)
        try specData.write(to: roomFolder.appendingPathComponent("spec.json"))
        let roomJSON = """
        {"id":"\(roomID)","planID":"\(planID)","slug":"smoke-room","tenant":"tenant:gujo"}
        """
        try Data(roomJSON.utf8).write(to: roomFolder.appendingPathComponent("ROOM.json"))
        let envPairs = [
            "HOME=\(root.path)",
            "SWIFT_APP_STATE_ROOT=\(root.path)",
            "AGENT_ROOM_TERMINAL_DAEMON=\(daemon.path)",
            "PATH=\(path)",
            "ART_LEDGER_ARGV=\(argvLog.path)",
            "ART_PAD_FILE=\(pad.path)",
        ]
        return SmokeHarness(
            root: root,
            cli: cli,
            daemon: daemon,
            argvLogURL: argvLog,
            envPairs: envPairs,
            roomID: roomID,
            planID: planID
        )
    }

    func tearDown() {
        _ = run(["daemon", "stop", "--json"], timeout: 15)
        DaemonProcessReaper.reapDaemons(root: root)
        try? FileManager.default.removeItem(at: root)
    }

    private static let defaultTimeout: TimeInterval = 30

    func run(_ arguments: [String]) -> CommandResult {
        run(arguments, timeout: Self.defaultTimeout)
    }

    func run(_ arguments: [String], timeout: TimeInterval) -> CommandResult {
        var argv = envPairs
        argv.append(cli.path)
        argv.append(contentsOf: arguments)
        return CommandKitSync.run("/usr/bin/env", argv, timeout: timeout)
    }

    func jsonString(_ stdout: String, key: String) -> String? {
        guard let start = stdout.firstIndex(of: "{"),
              let data = String(stdout[start...]).data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let root: [String: Any]
        if let object = raw as? [String: Any] {
            if let result = object["result"] as? [String: Any] {
                root = result
            } else {
                root = object
            }
        } else {
            return nil
        }
        return root[key] as? String
    }

    func writeUsageOverHandoff(roomPath: String) throws {
        let url = URL(fileURLWithPath: roomPath)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("usage.jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let line = """
        {"inputTokens":700000,"outputTokens":0,"requests":1,"tool":"claude","ts":"2026-09-03T00:00:00Z"}
        """
        try Data((line + "\n").utf8).write(to: url)
        let alias = url.deletingPathExtension().appendingPathExtension("json")
        try Data((line + "\n").utf8).write(to: alias)
    }

    static func locate(_ name: String) throws -> URL {
        if let found = candidateURLs(name).first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) {
            return found
        }
        throw XCTSkip("\(name) is not built (.build/debug/\(name) missing)")
    }

    static func candidateURLs(_ name: String) -> [URL] {
        var urls: [URL] = []
        let file = URL(fileURLWithPath: #filePath)
        let packageRoot = file
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for suffix in [
            ".build/debug/\(name)",
            ".build/arm64-apple-macosx/debug/\(name)",
            ".build/x86_64-apple-macosx/debug/\(name)",
        ] {
            urls.append(packageRoot.appendingPathComponent(suffix))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent(".build/debug/\(name)"))
        urls.append(cwd.appendingPathComponent("apps/agent-room-terminal-swift/.build/debug/\(name)"))
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            urls.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(name))
        }
        return urls
    }

    static func writeStubs(bin: URL, argvLog: URL, pad: URL, roomID: String, planID: String) throws {
        let listJSON = listPayloadJSON(roomID: roomID, planID: planID)
        let listFile = pad.deletingLastPathComponent().appendingPathComponent("list.json")
        try Data(listJSON.utf8).write(to: listFile)
        let workTodo = """
        #!/bin/sh
        log="${ART_LEDGER_ARGV:-\(argvLog.path)}"
        printf '%s\\n' "$*" >> "$log"
        pad=$(cat "${ART_PAD_FILE:-\(pad.path)}")
        room='\(roomID)'
        list='\(listFile.path)'
        case " $* " in
          *" placement list "*|*" room list "*)
            printf '%s' "$(cat "$list")"
            printf '%s' "$pad"
            printf '%s\\n' '"}'
            ;;
          *" placement occupy "*|*" placement handover "*|*" placement tick "*)
            printf '%s\\n' '{"ok":true,"payload":{"roomID":"'"$room"'"}}'
            ;;
          *)
            printf '%s\\n' '{"ok":true,"payload":{"roomID":"'"$room"'"}}'
            ;;
        esac
        """
        let isolation = """
        #!/bin/sh
        printf '%s\\n' '{"ok":true,"result":{"compliant":true,"reason":"fixture"}}'
        """
        let ok = """
        #!/bin/sh
        printf '%s\\n' '{"ok":true}'
        """
        try writeExec(bin.appendingPathComponent("agent-work-todo"), workTodo)
        try writeExec(bin.appendingPathComponent("agent-tenant-isolation-manager"), isolation)
        try writeExec(bin.appendingPathComponent("agent-room-monitor"), ok)
        try writeExec(bin.appendingPathComponent("agent-wiki"), "#!/bin/sh\nprintf '%s\\n' wiki-id-1\n")
    }

    static func writeExec(_ url: URL, _ body: String) throws {
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func listPayloadJSON(roomID: String, planID: String) -> String {
        let walls = #"{"writePaths":["work/**"],"network":true}"#
        let blueprint = """
        {"slug":"gujo-seller-operations","task":"list files","verdict":"true",\
        "toolbelt":[],"wallPreset":"toolbelt","walls":\(walls),"brief":[],\
        "agentTools":["claude"]}
        """
        let roomObj = """
        {"id":"\(roomID)","blueprintSlug":"gujo-seller-operations",\
        "wallMode":"full","blueprint":\(blueprint)}
        """
        return """
        {"ok":true,"payload":[{"id":"\(planID)","tenantID":"tenant:gujo",\
        "rooms":[\(roomObj)]}],"pad":"
        """
    }
}
