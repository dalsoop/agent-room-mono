import Foundation
import AgentRoomTerminalCore
import RoomKit

extension DaemonServer {
    func ensureNetworkProxy(_ request: DaemonRequest) -> DaemonResponse {
        guard let roomDir = request.roomDir, !roomDir.isEmpty else {
            return DaemonResponse.failure(
                "ensureNetworkProxy requires roomDir",
                generation: generation
            )
        }
        do {
            let proxy = try proxies.ensure(
                roomDir: roomDir,
                domains: request.allowedDomains ?? []
            )
            return DaemonResponse.success(
                .object([
                    "proxyPort": .int(Int(proxy.port)),
                    "mode": .string("allow"),
                    "allowedDomains": .array(proxy.allowedDomains.map { .string($0) }),
                ]),
                generation: generation
            )
        } catch {
            return DaemonResponse.failure(error.localizedDescription, generation: generation)
        }
    }

    func events(_ request: DaemonRequest) -> DaemonResponse {
        guard let roomDir = request.roomDir, !roomDir.isEmpty else {
            return DaemonResponse.failure("events requires roomDir", generation: generation)
        }
        return DaemonResponse.success(.object(["subscribed": .bool(true)]), generation: generation)
    }

    func openSession(_ request: DaemonRequest) -> DaemonResponse {
        guard let roomDir = request.roomDir, let envFile = request.envFile else {
            return DaemonResponse.failure("openSession requires roomDir and envFile", generation: generation)
        }
        let shell = request.shell ?? "zsh -r"
        do {
            let env = try EnvFile.load(url: URL(fileURLWithPath: envFile))
            let sessionID = UUID().uuidString.lowercased()
            let role = request.sessionRole ?? RoomSessionRole.predecessor.rawValue
            // srt 백엔드 감지: spec.json 에서 sandboxBackend 를 읽는다
            let sandbox = SRTSessionResolver.sandboxConfig(
                roomDir: roomDir,
                fallbackProfile: request.seatbeltProfile
            ) { dir, event in
                recordEvent(roomDir: dir, event: event)
            }

            let session = PtyTerminalSession(
                sessionID: sessionID,
                roomDir: roomDir,
                env: env,
                sandbox: sandbox,
                ringLines: tuning.ringLines,
                ringByteCapacity: tuning.ringByteCapacity,
                sessionRole: role,
                dimensions: (request.columns != nil || request.rows != nil)
                    ? TerminalDimensions(columns: request.columns, rows: request.rows)
                    : nil
            )
            session.canUnseedCredentials = { [weak self] in
                guard let self else { return true }
                let remaining = self.sessionTable().sessions(inRoom: roomDir).filter { !$0.isExited }
                return remaining.isEmpty
            }
            try session.start(shell: shell, banner: request.banner)
            _ = session.subscribe(onOutput: { _ in }, onExit: { [weak self] code in
                self?.recordEvent(
                    roomDir: roomDir,
                    event: RoomEvent.sessionExited(code: Int(code), sessionID: sessionID)
                )
            })
            sessionTable().add(session)
            markOccupied()
            let tool = env["ROOM_TOOL"] ?? env["AGENT_TOOL"] ?? "terminal"
            recordEvent(
                roomDir: roomDir,
                event: RoomEvent.sessionStarted(sessionID: sessionID, pid: Int(session.pgid), tool: tool)
            )
            let result = JSONValue.object([
                "sessionID": .string(sessionID),
                "pgid": .int(Int(session.pgid)),
            ])
            return DaemonResponse.success(result, generation: generation)
        } catch {
            return DaemonResponse.failure(error.localizedDescription, generation: generation)
        }
    }

    func closeSession(_ request: DaemonRequest) -> DaemonResponse {
        guard let sessionID = request.sessionID else {
            return DaemonResponse.failure("closeSession requires sessionID", generation: generation)
        }
        guard let session = sessionTable().get(sessionID) else {
            return DaemonResponse.failure("unknown session", generation: generation)
        }
        session.close(grace: DaemonDefaults.closeGraceSeconds)
        sessionTable().remove(sessionID)
        let remaining = sessionTable().sessions(inRoom: session.roomDir).filter { !$0.isExited }
        if remaining.isEmpty {
            let roomURL = URL(fileURLWithPath: session.roomDir)
            RoomLifecycle.close(roomURL: roomURL)
            recordEvent(roomDir: session.roomDir, event: RoomEvent.closed(sessionID: sessionID))
        }
        markEmptyIfNeeded()
        return DaemonResponse.success(.object(["sessionID": .string(sessionID)]), generation: generation)
    }

    func exec(_ request: DaemonRequest) -> DaemonResponse {
        guard let roomDir = request.roomDir, let argv = request.argv else {
            return DaemonResponse.failure("exec requires roomDir and argv", generation: generation)
        }
        let restricted = request.sessionID
            .flatMap { sessionTable().get($0)?.restrictedShell } ?? true
        let writePaths = ExecPolicy.writePaths(roomDir: roomDir)
        var runArgv = argv
        var redirectReason: String?
        switch ExecPolicy.decision(argv: argv, restricted: restricted,
                                   roomDir: roomDir, writePaths: writePaths) {
        case .deny(let reason):
            return DaemonResponse.failure(reason, generation: generation)
        case .quarantine(let reason):
            return execQuarantine(roomDir: roomDir, argv: argv, reason: reason)
        case .redirect(let redirected, let reason):
            runArgv = redirected
            redirectReason = reason
        case .allow:
            break
        }
        let env = execEnvironment(sessionID: request.sessionID, roomDir: roomDir)
        let profile = execProfile(sessionID: request.sessionID, tool: request.tool, roomDir: roomDir)
        let timeoutSeconds = ExecTimeout.resolve(request.timeoutSeconds)
        let isRaw = request.raw ?? false
        guard let profile else {
            return DaemonResponse.failure(
                "방에 유효한 Seatbelt 프로파일이 없어 exec 를 거부합니다 (Fail-Closed). walls 설정을 확인하십시오.",
                generation: generation)
        }
        let isLaunch = request.launch ?? false
        let result: ExecRunner.Run
        if isRaw {
            result = ExecRunner.run(
                argv: runArgv, roomDir: roomDir, env: env,
                seatbeltProfile: profile, timeoutSeconds: timeoutSeconds)
        } else {
            result = runLaunchExec(
                roomDir: roomDir, argv: runArgv, env: env,
                profile: profile, timeout: timeoutSeconds,
                isLaunch: isLaunch)
        }
        recordExecEvents(roomDir: roomDir, argv: argv, runArgv: runArgv, result: result,
                         isVerdict: request.isVerdict)
        return execResponse(result: result, redirectReason: redirectReason)
    }

    func execQuarantine(roomDir: String, argv: [String], reason: String) -> DaemonResponse {
        let id = UUID().uuidString.lowercased()
        var errorText = "quarantine: \(reason)"
        do {
            let dir = URL(fileURLWithPath: roomDir)
                .appendingPathComponent("state/quarantine", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: ["argv": argv], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appendingPathComponent("\(id).json"))
        } catch {
            errorText += " (record failed: \(error.localizedDescription))"
        }
        return DaemonResponse(ok: false, result: .object(["quarantineID": .string(id)]),
                              error: errorText, generation: generation)
    }

    func recordExecEvents(roomDir: String, argv: [String], runArgv: [String],
                          result: ExecRunner.Run, isVerdict: Bool) {
        let verdict = isVerdict || argv.contains("--verdict") || runArgv.contains("--verdict")
        guard verdict else { return }
        let outStr = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let errStr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = outStr.isEmpty ? errStr : outStr
        recordEvent(roomDir: roomDir,
                    event: .verdictRan(exit: Int(result.exitCode), summary: summary))
    }

    func snapshot(_ request: DaemonRequest) -> DaemonResponse {
        guard let sessionID = request.sessionID else {
            return DaemonResponse.failure("snapshot requires sessionID", generation: generation)
        }
        guard let session = sessionTable().get(sessionID) else {
            return DaemonResponse.failure("unknown session", generation: generation)
        }
        let count = request.lines ?? 100
        let lines = session.snapshot(lines: count).map { JSONValue.string($0) }
        return DaemonResponse.success(.object(["lines": .array(lines)]), generation: generation)
    }

    func listSessions() -> DaemonResponse {
        let items = sessionTable().all().map { session in
            var dict: [String: JSONValue] = [
                "sessionID": .string(session.sessionID),
                "roomDir": .string(session.roomDir),
                "pgid": .int(Int(session.pgid)),
                "recovered": .bool(session.recovered),
                "sessionRole": .string(session.sessionRole),
            ]
            if session.hasExited {
                dict["exitCode"] = .int(Int(session.recordedExitCode))
            }
            return JSONValue.object(dict)
        }
        return DaemonResponse.success(
            .object([
                "sessions": .array(items),
                "generation": .int(Int(generation)),
            ]),
            generation: generation
        )
    }

    func tuning(_ request: DaemonRequest) -> DaemonResponse {
        let action = request.tuningAction ?? "get"
        if action == "set" {
            applyTuning(key: request.tuningKey, value: request.tuningValue)
        }
        return DaemonResponse.success(
            .object([
                "idleSeconds": .double(tuning.idleSeconds),
                "ringLines": .int(tuning.ringLines),
                "ringBytes": .int(tuning.ringByteCapacity),
            ]),
            generation: generation
        )
    }

    func input(_ request: DaemonRequest) -> DaemonResponse {
        guard let sessionID = request.sessionID else {
            return DaemonResponse.failure("input requires sessionID and input", generation: generation)
        }
        guard let session = sessionTable().get(sessionID) else {
            return DaemonResponse.failure("unknown session", generation: generation)
        }
        if let blob = request.bytes {
            guard let data = Data(base64Encoded: blob) else {
                return DaemonResponse.failure("input bytes must be base64", generation: generation)
            }
            session.send(data)
        } else if let text = request.input {
            session.send(text)
        } else {
            return DaemonResponse.failure("input requires sessionID and input", generation: generation)
        }
        return DaemonResponse.success(.object(["sessionID": .string(sessionID)]), generation: generation)
    }

    func attach(_ request: DaemonRequest) -> DaemonResponse {
        guard let sessionID = request.sessionID else {
            return DaemonResponse.failure("attach requires sessionID", generation: generation)
        }
        guard let session = sessionTable().get(sessionID) else {
            return DaemonResponse.failure("unknown session", generation: generation)
        }
        if session.recovered {
            return DaemonResponse.failure("session recovered, attach unavailable", generation: generation)
        }
        var body: [String: JSONValue] = [
            "attached": .bool(true),
        ]
        if let replayBytes = request.replayBytes {
            body["replayBytes"] = .int(replayBytes)
        }
        if request.lines != nil || request.replayBytes == nil {
            let count = request.lines ?? 100
            let lines = session.snapshot(lines: count).map { JSONValue.string($0) }
            body["snapshot"] = .array(lines)
        }
        return DaemonResponse.success(
            .object(body),
            generation: generation
        )
    }

    func resize(_ request: DaemonRequest) -> DaemonResponse {
        guard let sessionID = request.sessionID,
              let columns = request.columns,
              let rows = request.rows else {
            return DaemonResponse.failure("resize requires sessionID, columns, and rows", generation: generation)
        }
        guard columns > 0, rows > 0 else {
            return DaemonResponse.failure("resize columns and rows must be positive", generation: generation)
        }
        guard let session = sessionTable().get(sessionID) else {
            return DaemonResponse.failure("unknown session", generation: generation)
        }
        if session.recovered {
            return DaemonResponse.failure("session recovered, resize unavailable", generation: generation)
        }
        session.resize(columns: columns, rows: rows)
        return DaemonResponse.success(
            .object([
                "sessionID": .string(sessionID),
                "columns": .int(columns),
                "rows": .int(rows),
            ]),
            generation: generation
        )
    }

    func authorize(_ request: DaemonRequest) -> DaemonResponse? {
        if let missing = missingTargetSession(request) {
            return missing
        }
        let requester = resolveRequester(request)
        let target = resolveTarget(request)
        if SessionAuthorizer.allows(requester: requester, target: target) {
            return nil
        }
        return DaemonResponse.failure(SessionAuthorizer.foreignRoomError, generation: generation)
    }

    private func missingTargetSession(_ request: DaemonRequest) -> DaemonResponse? {
        switch request.op {
        case .closeSession, .snapshot, .attach, .input, .resize:
            guard let sessionID = request.sessionID else { return nil }
            if sessionTable().get(sessionID) == nil {
                return DaemonResponse.failure("unknown session", generation: generation)
            }
            return nil
        case .exec:
            if let sessionID = request.sessionID, sessionTable().get(sessionID) == nil {
                return DaemonResponse.failure("unknown session", generation: generation)
            }
            return nil
        case .openSession, .listSessions, .tuning, .ensureNetworkProxy, .events:
            return nil
        }
    }

    private func resolveRequester(_ request: DaemonRequest) -> SessionPrincipal {
        if request.authority == SessionAuthorizer.commandRoomAuthority {
            return .commandRoom(sessionID: request.roomSession ?? request.sessionID)
        }
        let requesterID: String?
        switch request.op {
        case .exec:
            requesterID = request.roomSession ?? request.sessionID
        default:
            requesterID = request.roomSession
        }
        let roomDir = requesterID.flatMap { sessionTable().get($0)?.roomDir }
        return SessionPrincipal(
            sessionID: requesterID,
            roomDir: roomDir,
            authority: request.authority
        )
    }

    private func resolveTarget(_ request: DaemonRequest) -> SessionPrincipal {
        switch request.op {
        case .exec, .openSession, .ensureNetworkProxy, .events:
            return SessionPrincipal(sessionID: nil, roomDir: request.roomDir)
        case .closeSession, .snapshot, .attach, .input, .resize:
            let sessionID = request.sessionID
            let roomDir = sessionID.flatMap { sessionTable().get($0)?.roomDir } ?? request.roomDir
            return SessionPrincipal(sessionID: sessionID, roomDir: roomDir)
        case .listSessions, .tuning:
            return SessionPrincipal()
        }
    }

    private func execEnvironment(sessionID: String?, roomDir: String) -> [String: String] {
        if let sessionID, let session = sessionTable().get(sessionID) {
            return session.env
        }
        return ["PWD": roomDir]
    }

}
