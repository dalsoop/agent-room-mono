import Foundation
import CommandKit
import XCTest
import RoomKit
@testable import AgentRoomTerminalCore

enum CLITestSupport {
    static let roomID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    static let planID = "550e8400-e29b-41d4-a716-446655440000"
    static let slug = "gujo-seller-operations"

    static func product(_ name: String) -> URL? {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            let url = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func runCLI(
        _ url: URL,
        _ arguments: [String],
        extraEnv: [String: String] = [:],
        timeout: TimeInterval = 25
    ) -> (exit: Int32, stdout: String, stderr: String) {
        let roomEnvs = [
            "ROOM_ID", "ROOM_SESSION", "ROOM_PRESET", "ROOM_PARENT", "ROOM_TENANT"
        ]
        var unsets: [String] = []
        for key in roomEnvs where extraEnv[key] == nil && ProcessInfo.processInfo.environment[key] != nil {
            unsets.append(contentsOf: ["-u", key])
        }
        let pairs = extraEnv.map { key, value in
            "\(key)=\(value.replacingOccurrences(of: "\0", with: ""))"
        }
        let result = CommandKitSync.run(
            "/usr/bin/env",
            unsets + pairs + [url.path] + arguments,
            timeout: timeout
        )
        return (result.exitCode, result.stdout, result.stderr)
    }

    static func json(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func payload(_ stdout: String) -> [String: Any]? {
        json(stdout)?["result"] as? [String: Any]
    }

    static func roomPath(root: URL) -> String {
        RoomPaths.roomDirectory(
            tenant: "gujo",
            roomID: roomID,
            homeDirectory: root.path
        ).path
    }

    struct LedgerFixture {
        var occupant: String = ""
        var occupantSession: String = ""
        var successorOccupant: String = ""
        var successorSession: String = ""
        var handoverState: String = "none"
        var toolbelt: [String] = []
        var verdict: String = "ls"
        var occupyFail: Bool = false
        var wallPreset: String = "toolbelt"
        var writePaths: [String] = ["work/**"]
        var network: Bool = true
    }

    static func writeFixtureCLIs(root: URL, fixture: LedgerFixture = LedgerFixture()) throws {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("ledger.log")
        let toolbeltJSON = try String(
            data: JSONEncoder().encode(fixture.toolbelt),
            encoding: .utf8
        ) ?? "[]"
        let writeJSON = try String(
            data: JSONEncoder().encode(fixture.writePaths),
            encoding: .utf8
        ) ?? "[]"
        let occupyFail = fixture.occupyFail ? "1" : "0"
        let workTodo = """
        #!/usr/bin/env python3
        import json, os, sys
        log = os.environ.get("LEDGER_LOG", r"\(log.path)")
        argv = sys.argv[1:]
        mutate = any(x in argv for x in ("occupy", "tick", "handover", "spawn-room"))
        if mutate:
            open(log, "a").write(" ".join(argv) + "\\n")
        if "occupy" in argv and "\(occupyFail)" == "1":
            sys.stderr.write("occupy denied\\n")
            sys.exit(1)
        if "list" in argv:
            print(json.dumps({
              "ok": True,
              "payload": [{
                "id": "\(planID)",
                "tenantID": "tenant:gujo",
                "rooms": [{
                  "id": "\(roomID)",
                  "blueprintSlug": "\(slug)",
                  "wallMode": "full",
                  "occupant": "\(fixture.occupant)",
                  "occupantSession": "\(fixture.occupantSession)",
                  "successorOccupant": "\(fixture.successorOccupant)",
                  "successorSession": "\(fixture.successorSession)",
                  "handoverState": "\(fixture.handoverState)",
                  "blueprint": {
                    "slug": "\(slug)",
                    "task": "list files",
                    "verdict": "\(fixture.verdict)",
                    "toolbelt": \(toolbeltJSON),
                    "wallPreset": "\(fixture.wallPreset)",
                    "walls": {"writePaths": \(writeJSON), "network": \(fixture.network ? "True" : "False")},
                    "brief": [],
                    "agentTools": ["claude"]
                  }
                }]
              }]
            }))
            sys.exit(0)
        print(json.dumps({"ok": True, "payload": {"roomID": "\(roomID)"}}))
        """
        let isolation = """
        #!/usr/bin/env python3
        import json, sys
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        compliant = name != "bad-cli"
        print(json.dumps({"ok": True, "result": {"compliant": compliant, "reason": "fixture"}}))
        """
        try writeExec(bin.appendingPathComponent("agent-work-todo"), workTodo)
        try writeExec(bin.appendingPathComponent("agent-tenant-isolation-manager"), isolation)
        try writeExec(
            bin.appendingPathComponent("agent-room-monitor"),
            "#!/usr/bin/env python3\nimport json\nprint(json.dumps({\"ok\": True}))\n"
        )
        try writeExec(
            bin.appendingPathComponent("agent-wiki"),
            "#!/usr/bin/env python3\nprint(\"wiki-id-1\")\n"
        )

        let roomFolder = URL(fileURLWithPath: roomPath(root: root))
        try FileManager.default.createDirectory(at: roomFolder, withIntermediateDirectories: true)
        let roomJSON = """
        {"id":"\(roomID)","planID":"\(planID)","slug":"\(slug)","tenant":"tenant:gujo"}
        """
        try Data(roomJSON.utf8).write(to: roomFolder.appendingPathComponent("ROOM.json"))

        let spec = RoomSpec(
            roomID: UUID(uuidString: roomID) ?? UUID(),
            tenant: "tenant:gujo",
            task: "list files",
            verdict: fixture.verdict,
            walls: RoomWalls(
                filesystem: FilesystemWall(allowWrite: fixture.writePaths),
                network: fixture.network ? .open : .closed
            ),
            launch: RoomLaunch(tool: .claude),
            executionPolicy: RoomExecutionPolicy(
                lineage: RoomLineage(planID: planID, blueprintSlug: slug),
                budget: .zero
            )
        )
        let specData = try JSONEncoder().encode(spec)
        var specDict = (try? JSONSerialization.jsonObject(with: specData) as? [String: Any]) ?? [:]
        specDict["toolbelt"] = fixture.toolbelt
        specDict["preset"] = fixture.wallPreset
        specDict["wallMode"] = "full"
        specDict["successorOccupant"] = fixture.successorOccupant
        specDict["successorSession"] = fixture.successorSession
        specDict["handoverState"] = fixture.handoverState
        let finalData = (try? JSONSerialization.data(withJSONObject: specDict)) ?? specData
        try finalData.write(to: roomFolder.appendingPathComponent("spec.json"))

        let canonicalFolder = root
            .appendingPathComponent(".tenants", isDirectory: true)
            .appendingPathComponent("gujo", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent(roomID, isDirectory: true)
        try FileManager.default.createDirectory(at: canonicalFolder, withIntermediateDirectories: true)
        try finalData.write(to: canonicalFolder.appendingPathComponent("spec.json"))
        try Data(roomJSON.utf8).write(to: canonicalFolder.appendingPathComponent("ROOM.json"))

        if !fixture.occupant.isEmpty || !fixture.occupantSession.isEmpty {
            let event = RoomEvent.occupied(agent: fixture.occupant, sessionID: fixture.occupantSession)
            _ = try? RoomEventLog(roomURL: roomFolder).append(event)
            _ = try? RoomEventLog(roomURL: canonicalFolder).append(event)
        }
    }

    static func writeExec(_ url: URL, _ body: String) throws {
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func writeFakeDaemon(root: URL) throws -> URL {
        let url = root.appendingPathComponent("fake-daemon.py")
        let body = """
        #!/usr/bin/env python3
        import json, os, socket, struct, sys, uuid

        sock_path, log_path, ready_path = sys.argv[1], sys.argv[2], sys.argv[3]
        preload_id = sys.argv[4] if len(sys.argv) > 4 else ""
        preload_room = sys.argv[5] if len(sys.argv) > 5 else ""
        sessions = {}
        if preload_id and preload_room:
            sessions[preload_id] = {"roomDir": preload_room, "sessionRole": "predecessor"}

        def recvn(conn, n):
            buf = b""
            while len(buf) < n:
                chunk = conn.recv(n - len(buf))
                if not chunk:
                    return None
                buf += chunk
            return buf

        def reply(conn, obj):
            body = json.dumps(obj).encode()
            conn.sendall(struct.pack(">I", len(body)) + body)

        os.makedirs(os.path.dirname(sock_path), exist_ok=True)
        if os.path.exists(sock_path):
            os.unlink(sock_path)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(sock_path)
        server.listen(32)
        open(ready_path, "w").write("ok")
        while True:
            conn, _ = server.accept()
            try:
                hdr = recvn(conn, 4)
                if not hdr:
                    continue
                n = struct.unpack(">I", hdr)[0]
                payload = recvn(conn, n)
                if not payload:
                    continue
                req = json.loads(payload.decode())
                with open(log_path, "a") as fh:
                    fh.write(json.dumps(req) + "\\n")
                op = req.get("op")
                if op == "openSession":
                    sid = str(uuid.uuid4())
                    role = req.get("sessionRole") or "predecessor"
                    sessions[sid] = {"roomDir": req.get("roomDir") or "", "sessionRole": role}
                    reply(conn, {"ok": True, "generation": 1,
                                 "result": {"sessionID": sid, "pgid": 1, "sessionRole": role}})
                elif op == "closeSession":
                    sid = req.get("sessionID") or ""
                    sessions.pop(sid, None)
                    reply(conn, {"ok": True, "generation": 1,
                                 "result": {"sessionID": sid}})
                elif op == "listSessions":
                    items = [{"sessionID": i, "roomDir": d.get("roomDir", ""),
                              "pgid": 1, "sessionRole": d.get("sessionRole", "predecessor")}
                             for i, d in sessions.items()]
                    reply(conn, {"ok": True, "generation": 1,
                                 "result": {"sessions": items}})
                elif op == "ensureNetworkProxy":
                    reply(conn, {"ok": True, "generation": 1,
                                 "result": {"proxyPort": 18080, "mode": "allow"}})
                else:
                    reply(conn, {"ok": True, "generation": 1, "result": {}})
            finally:
                conn.close()
        """
        try writeExec(url, body)
        return url
    }

    @discardableResult
    static func startFakeDaemon(
        root: URL,
        preloadID: String = "",
        preloadRoom: String = ""
    ) throws -> RunningProcess {
        let script = try writeFakeDaemon(root: root)
        let socket = AppPaths.daemonSocketURL(
            environment: ["SWIFT_APP_STATE_ROOT": root.path]
        )
        try FileManager.default.createDirectory(
            at: socket.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let log = root.appendingPathComponent("daemon-requests.jsonl")
        let ready = root.appendingPathComponent("daemon-ready")
        var args = [script.path, socket.path, log.path, ready.path]
        if !preloadID.isEmpty {
            args += [preloadID, preloadRoom]
        }
        let process = try CommandKitSync.spawn("/usr/bin/python3", args)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: ready.path) {
                return process
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.terminate()
        throw NSError(
            domain: "CLITestSupport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "fake daemon did not become ready"]
        )
    }

    static func requestLog(root: URL) throws -> [[String: Any]] {
        let log = root.appendingPathComponent("daemon-requests.jsonl")
        guard FileManager.default.fileExists(atPath: log.path) else { return [] }
        let text = try String(contentsOf: log, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    static func ledgerLog(root: URL) throws -> [String] {
        let url = root.appendingPathComponent("ledger.log")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    static func openEnv(root: URL) -> [String: String] {
        let bin = root.appendingPathComponent("bin")
        return [
            "SWIFT_APP_STATE_ROOT": root.path,
            "PATH": bin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            "LEDGER_LOG": root.appendingPathComponent("ledger.log").path,
        ]
    }
}
