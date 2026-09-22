import Foundation
import AgentRoomTerminalCore
import RoomKit
import CommandKit

enum CloseCommand {
    static let usageText = "usage: close <room-id> [--execute] [--json]"

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }
        let execute = CLIArgs.takeExecute(&rest)
        _ = CLIArgs.takeJSON(&rest)
        guard let roomID = rest.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        if !execute {
            CLIIO.printOKObject(DryRunPlan.object(
                command: "close",
                roomID: roomID,
                steps: ["daemon-closeSession", "events-vacate", "events-close", "cognitive-delta-evaluation"]
            ))
            return
        }
        CLIAsync.run {
            try await executeClose(roomID: roomID)
        }
    }

    static func executeClose(roomID: String) async throws {
        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)
        let client = DaemonCommand.commandRoomClient()
        let session = try sessionID(roomURL: roomURL, client: client)
        if let session {
            _ = try client.send(.closeSession(sessionID: session))
        }

        // 인지 원장 기계 실측 평가 (Precompute가 존재하면 Delta 자동 산출 및 시냅스 결선)
        let layout = RoomVaultLayout(roomURL: roomURL)
        let ledger = RoomCognitiveLedger()
        var cognitiveVerdict: String?
        var cognitiveDriftScore: Double?

        if let precompute = ledger.readPrecompute(in: layout) {
            let probe = RoomMechanicalProbe()
            let measurement = DeltaCommand.measureRoomExecution(roomURL: roomURL, isBreakGlass: false, reason: nil as String?)
            let delta = probe.evaluate(precompute: precompute, measurement: measurement)
            do {
                _ = try ledger.recordDelta(delta, in: layout)
            } catch {
                fputs("warning: failed to record cognitive delta on close: \(error.localizedDescription)\n", stderr)
            }
            cognitiveVerdict = delta.verdict.rawValue
            cognitiveDriftScore = delta.driftScore
        }

        _ = RoomLifecycle.close(roomURL: roomURL)
        let eventLog = RoomEventLog(roomURL: roomURL)
        _ = try eventLog.append(RoomEvent.vacated(reason: "closed by agent-room-terminal close", by: "cli"))
        _ = try eventLog.append(RoomEvent.closed(by: "cli"))
        CLIIO.printOKObject(closeResult(
            roomID: roomID,
            ledgerVacate: "settled",
            ledgerRetries: 0,
            partial: false,
            cognitiveVerdict: cognitiveVerdict,
            cognitiveDriftScore: cognitiveDriftScore
        ))
    }

    static func closeResult(
        roomID: String,
        ledgerVacate: String,
        ledgerRetries: Int,
        partial: Bool,
        cognitiveVerdict: String? = nil,
        cognitiveDriftScore: Double? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "roomID": roomID,
            "closed": true,
            "dryRun": false,
            "ledgerVacate": ledgerVacate,
            "ledgerRetries": ledgerRetries,
        ]
        if let verdict = cognitiveVerdict {
            result["cognitiveVerdict"] = verdict
        }
        if let score = cognitiveDriftScore {
            result["cognitiveDriftScore"] = score
        }
        if partial {
            result["partial"] = true
        }
        return result
    }
}

enum ExecCommand {
    static let usageText = """
        usage: exec <room-id> [--raw] [--tool claude|codex|grok|agy] \
        [--timeout N] -- <command…>

        기본은 방 세션 안에서 실행합니다. \
        --raw 를 붙이면 동기 프로세스로 실행하되 방 세션이 없으면 거부합니다.
        """

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }
        let argv = CLIArgs.afterDashDash(rest) ?? []
        rest = rest.split(separator: "--", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { Array($0) } ?? rest
        let timeoutRaw = CLIArgs.value("--timeout", in: rest)
        let raw = CLIArgs.takeFlag("--raw", from: &rest)
        let toolValue = CLIArgs.value("--tool", in: rest)
        // --launch 는 하위 호환용. 지정하지 않으면 기본 launch(비 raw).
        _ = CLIArgs.takeFlag("--launch", from: &rest)
        let positionals = CLIArgs.dropFlags(
            rest, flags: ["--json"], valueFlags: ["--timeout", "--tool"])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        guard !argv.isEmpty else {
            CLIIO.fail("exec requires a command after --", code: CLIExit.usage)
        }
        let timeoutSeconds: Int
        do {
            timeoutSeconds = try ExecTimeout.parse(timeoutRaw)
        } catch {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        do {
            try runExec(roomID: roomID, argv: argv, timeoutSeconds: timeoutSeconds, raw: raw, tool: toolValue)
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func runExec(
        roomID: String,
        argv: [String],
        timeoutSeconds: Int = ExecTimeout.defaultSeconds,
        raw: Bool = false,
        tool: String? = nil
    ) throws {
        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)
        let client = DaemonCommand.commandRoomClient()
        let session = try sessionID(roomURL: roomURL, client: client)
        let started = Date()
        let response = try client.send(
            .exec(
                sessionID: session,
                roomDir: roomURL.path,
                argv: argv,
                timeoutSeconds: timeoutSeconds,
                launch: raw ? nil : true,
                raw: raw ? true : nil,
                tool: tool
            )
        )
        let durationMs = Int(Date().timeIntervalSince(started) * 1000)
        guard response.ok else {
            throw DaemonProtocolError.requestFailed(response.error ?? "exec failed")
        }
        let exitCode = response.result?["exitCode"]?.int ?? 1
        let timedOut = response.result?["timedOut"]?.bool ?? false
        let tool = agentToolName(roomID: roomID, environment: env, argv: argv)
        do {
            try HabitCandidateStore.append(
                in: roomURL,
                argv: argv,
                exitCode: exitCode,
                durationMs: durationMs,
                tool: tool
            )
        } catch {
            FileHandle.standardError.write(
                Data(("habit candidate record failed: \(error.localizedDescription)\n").utf8)
            )
        }
        var output: [String: Any] = [
            "exit": exitCode,
            "exitCode": exitCode,
            "stdout": response.result?["stdout"]?.string ?? "",
            "stderr": response.result?["stderr"]?.string ?? "",
            "timedOut": timedOut,
        ]
        if let truncated = response.result?["truncated"]?.bool, truncated {
            output["truncated"] = true
        }
        CLIIO.printOKObject(output)
        if exitCode != 0 {
            exit(Int32(exitCode))
        }
    }
}

enum SnapshotCommand {
    static func run(_ args: [String]) {
        let rest = Array(args.dropFirst())
        let lines = Int(CLIArgs.value("--lines", in: rest) ?? "100") ?? 100
        let positionals = CLIArgs.dropFlags(rest, flags: ["--json"], valueFlags: ["--lines"])
        guard let roomID = positionals.first else {
            CLIIO.fail("usage: snapshot <room-id> [--lines N]", code: CLIExit.usage)
        }
        do {
            try runSnapshot(roomID: roomID, lines: lines)
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func runSnapshot(roomID: String, lines: Int) throws {
        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)
        let client = DaemonCommand.commandRoomClient()
        guard let session = try sessionID(roomURL: roomURL, client: client) else {
            CLIIO.fail("no live session for room \(roomID)")
        }
        let response = try client.send(.snapshot(sessionID: session, lines: lines))
        guard response.ok else {
            throw DaemonProtocolError.requestFailed(response.error ?? "snapshot failed")
        }
        let textLines = response.result?["lines"]?.array?.compactMap(\.string) ?? []
        CLIIO.printOKObject(["roomID": roomID, "lines": textLines])
    }
}

enum LaunchLogCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        let follow = CLIArgs.takeFlag("--follow", from: &rest)
        let tailRaw = CLIArgs.value("--tail", in: rest)
        let tail = tailRaw.flatMap { Int($0) }
        let positionals = CLIArgs.dropFlags(rest, flags: ["--json"], valueFlags: ["--tail"])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(
                "usage: launch-log <room-id> [--tail N] [--follow]",
                code: CLIExit.usage)
        }
        let env = ProcessInfo.processInfo.environment
        let roomURL: URL
        do {
            roomURL = try requireRoom(roomID: roomID, environment: env)
        } catch {
            CLIIO.fail("room not found: \(roomID)")
        }
        let logURL = roomURL.appendingPathComponent("launch.log")
        if follow {
            runFollow(logURL: logURL, tail: tail)
        } else {
            runStatic(logURL: logURL, tail: tail)
        }
    }

    private static func runStatic(logURL: URL, tail: Int?) {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            CLIIO.printOKObject(["lines": [String](), "path": logURL.path] as [String: Any])
            return
        }
        do {
            let content = try String(contentsOf: logURL, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")
            if lines.last?.isEmpty == true { lines.removeLast() }
            if let tail, tail < lines.count {
                lines = Array(lines.suffix(tail))
            }
            CLIIO.printOKObject(["lines": lines, "path": logURL.path] as [String: Any])
        } catch {
            CLIIO.fail("failed to read launch log: \(error.localizedDescription)")
        }
    }

    private static func runFollow(logURL: URL, tail: Int?) {
        if FileManager.default.fileExists(atPath: logURL.path) {
            do {
                let content = try String(contentsOf: logURL, encoding: .utf8)
                var lines = content.components(separatedBy: "\n")
                if lines.last?.isEmpty == true { lines.removeLast() }
                if let tail, tail < lines.count {
                    lines = Array(lines.suffix(tail))
                }
                for line in lines {
                    print(line) // allow:debug — CLI human stdout
                }
            } catch {
                fputs("launch-log: initial read: \(error.localizedDescription)\n", stderr)
            }
        }
        fflush(stdout)
        var lastSize = fileSize(logURL)
        while true {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            let currentSize = fileSize(logURL)
            guard currentSize > lastSize else { continue }
            do {
                let handle = try FileHandle(forReadingFrom: logURL)
                handle.seek(toFileOffset: lastSize)
                let newData = Data(safeResult.stdout.utf8)
                do { try handle.close() } catch {
                    fputs("launch-log: close: \(error.localizedDescription)\n", stderr)
                }
                if let text = String(data: newData, encoding: .utf8) {
                    print(text, terminator: "") // allow:debug — CLI human stdout
                    fflush(stdout)
                }
                lastSize = currentSize
            } catch {
                continue
            }
        }
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return attrs[.size] as? UInt64 ?? 0
        } catch {
            return 0
        }
    }
}

func agentToolName(roomID: String, environment: [String: String], argv: [String]) -> String {
    do {
        if let hit = try LedgerLookup.findRoom(roomID: roomID, environment: environment) {
            let occupant = hit.occupant
            if occupant.hasPrefix("agent:") {
                let rest = occupant.dropFirst(6)
                if let name = rest.split(separator: "@").first, !name.isEmpty {
                    return String(name)
                }
            }
        }
    } catch {
        FileHandle.standardError.write(
            Data(("habit candidate tool lookup failed: \(error.localizedDescription)\n").utf8)
        )
    }
    return argv.first ?? ""
}

func requireRoom(roomID: String, environment: [String: String]) throws -> URL {
    if let url = try RoomFolderLocator.find(roomID: roomID, environment: environment) {
        return url
    }
    throw LedgerLookupError.roomMissing(roomID)
}

func sessionID(roomURL: URL, client: DaemonClient) throws -> String? {
    let response = try client.send(.listSessions())
    guard response.ok else { return nil }
    let sessions = response.result?["sessions"]?.array ?? []
    let path = SessionAuthorizer.standardized(roomURL.path)
    let matching = sessions.filter { item in
        guard let dir = item["roomDir"]?.string else { return false }
        guard item["exitCode"] == nil && item["recovered"]?.bool != true else { return false }
        return SessionAuthorizer.standardized(dir) == path
    }
    if let envID = ProcessInfo.processInfo.environment["ROOM_SESSION"], !envID.isEmpty {
        if matching.contains(where: { $0["sessionID"]?.string == envID }) {
            return envID
        }
    }
    if let successor = matching.first(where: {
        $0["sessionRole"]?.string == RoomSessionRole.successor.rawValue
    }) {
        return successor["sessionID"]?.string
    }
    return matching.first?["sessionID"]?.string
}
