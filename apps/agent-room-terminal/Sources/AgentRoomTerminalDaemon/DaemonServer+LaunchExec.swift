import Foundation
import AgentRoomTerminalCore

// MARK: - 방 에이전트 기동 추상화

/// 방 에이전트 기동(launch exec)의 실행부 추상화.
/// `pty`(기본)는 데몬이 프로세스를 직접 굴리고, `herdr`는 herdr CLI 가 PTY 를 소유한다.
protocol RoomAgentLaunching {
    var name: String { get }
    func launch(_ command: RoomAgentLaunchCommand) throws -> RoomAgentLaunchResult
}

/// 백엔드에 전달하는 기동 명령. `onStarted`는 세션 id 가 확정되는 시점(pty 는 실행 직전,
/// herdr 는 pane id 획득 직후)에 정확히 한 번 호출한다.
struct RoomAgentLaunchCommand {
    var argv: [String]
    var roomDir: String
    /// 방 폴더 이름 — herdr 백엔드가 `ROOM_ID`·label 로 쓴다.
    var roomID: String
    var env: [String: String]
    var seatbeltProfile: String?
    var timeoutSeconds: Int
    var onOutput: (Data) -> Void
    var onStarted: (String) -> Void
}

/// 기동 결과. `sessionID`는 pty 백엔드의 `exec-<uuid>`, herdr 백엔드의 pane id 다.
struct RoomAgentLaunchResult {
    var sessionID: String
    var run: ExecRunner.Run
}

/// 기본 백엔드 — 기존 launch exec 경로(`ExecRunner.runStreaming`)를 그대로 감싼다.
struct PtyExecLaunchBackend: RoomAgentLaunching {
    let name = "pty"

    func launch(_ command: RoomAgentLaunchCommand) throws -> RoomAgentLaunchResult {
        let sid = "exec-\(UUID().uuidString.lowercased())"
        command.onStarted(sid)
        let run = ExecRunner.runStreaming(
            argv: command.argv, roomDir: command.roomDir, env: command.env,
            seatbeltProfile: command.seatbeltProfile,
            timeoutSeconds: command.timeoutSeconds,
            onOutput: command.onOutput)
        return RoomAgentLaunchResult(sessionID: sid, run: run)
    }
}

/// 백엔드 선택 스위치. 환경변수 `AGENT_ROOM_LAUNCH_BACKEND=herdr` 로만 herdr 가 켜지고
/// 그 외 전부(미설정 포함)는 기존 pty 다. 기본값 변경 금지.
enum LaunchBackendFactory {
    static let environmentKey = "AGENT_ROOM_LAUNCH_BACKEND"

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RoomAgentLaunching {
        switch environment[environmentKey]?.lowercased() {
        case "herdr":
            return HerdrLaunchBackend()
        default:
            return PtyExecLaunchBackend()
        }
    }
}

// MARK: - launch exec 처리

extension DaemonServer {
    func runLaunchExec(
        roomDir: String, argv: [String], env: [String: String],
        profile: String?, timeout: Int, isLaunch: Bool = true
    ) -> ExecRunner.Run {
        let backend = launchBackend
        let roomURL = URL(fileURLWithPath: roomDir)

        let sampler = makeBudgetSampler(roomURL: roomURL, env: env)
        sampler?.start()

        let logWriter = LaunchLogWriter(
            url: roomURL.appendingPathComponent("launch.log"),
            errorLog: logURL)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let ptySessions = sessionTable().sessions(inRoom: roomDir)

        var startedSessionID: String?
        var execSession: PtyTerminalSession?
        let command = RoomAgentLaunchCommand(
            argv: argv,
            roomDir: roomDir,
            roomID: roomURL.lastPathComponent,
            env: env,
            seatbeltProfile: profile,
            timeoutSeconds: timeout,
            onOutput: { chunk in
                logWriter.write(chunk)
                execSession?.injectOutput(chunk)
                guard !ptySessions.isEmpty else { return }
                let converted = ExecRunner.convertLFtoCRLF(chunk)
                for session in ptySessions {
                    session.injectOutput(converted)
                }
            },
            onStarted: { sid in
                startedSessionID = sid
                let session = PtyTerminalSession.execSession(
                    sessionID: sid,
                    roomDir: roomDir,
                    ringLines: self.tuning.ringLines,
                    ringByteCapacity: self.tuning.ringByteCapacity
                )
                execSession = session
                self.sessionTable().add(session)
                logWriter.write("--- \(timestamp) \(sid) 시작: \(argv.prefix(5).joined(separator: " ")) ---\n")
                if isLaunch {
                    self.recordEvent(roomDir: roomDir, event: .sessionStarted(sessionID: sid, pid: 0, tool: "exec"))
                }
            })

        do {
            let outcome = try backend.launch(command)
            sampler?.stopAndFlush()
            logWriter.write("--- \(outcome.sessionID) 종료 code=\(outcome.run.exitCode) ---\n")
            logWriter.close()
            _ = sessionTable().remove(outcome.sessionID)
            if isLaunch {
                recordEvent(roomDir: roomDir, event: .sessionExited(code: Int(outcome.run.exitCode), sessionID: outcome.sessionID))
            }
            return outcome.run
        } catch {
            sampler?.stopAndFlush()
            logWriter.write("--- backend \(backend.name) 실패: \(error.localizedDescription) ---\n")
            logWriter.close()
            if let sid = startedSessionID {
                _ = sessionTable().remove(sid)
                if isLaunch {
                    recordEvent(roomDir: roomDir, event: .sessionExited(code: 1, sessionID: sid))
                }
            }
            return ExecRunner.Run(
                stdout: "",
                stderr: "launch backend \(backend.name): \(error.localizedDescription)",
                exitCode: 1,
                timedOut: false)
        }
    }

    private func makeBudgetSampler(roomURL: URL, env: [String: String]) -> BudgetSampler? {
        let specURL = roomURL.appendingPathComponent(RoomPaths.specFileName)
        let legacyURL = roomURL.appendingPathComponent(RoomPaths.legacyRoomJSONName)
        let fileURL = FileManager.default.fileExists(atPath: specURL.path) ? specURL : legacyURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let budgetObj = json?["budget"] as? [String: Any]
            let initialInput = budgetObj?["initialInput"] as? Int ?? 0
            let toolStr = (json?["tool"] as? String)
                ?? (env["ROOM_TOOL"] as String?)
                ?? AgentRoomTool.claude.rawValue
            let tool = AgentRoomTool(rawValue: toolStr) ?? .claude
            return BudgetSampler(
                roomURL: roomURL,
                tool: tool,
                initialInput: initialInput
            )
        } catch {
            DaemonLog.append("budget-sampler-init: \(error.localizedDescription)", to: logURL)
            return nil
        }
    }

    func execResponse(result: ExecRunner.Run, redirectReason: String?) -> DaemonResponse {
        var body: [String: JSONValue] = [
            "exitCode": .int(Int(result.exitCode)),
            "stdout": .string(result.stdout),
            "stderr": .string(result.stderr),
            "timedOut": .bool(result.timedOut),
        ]
        if result.truncated {
            body["truncated"] = .bool(true)
        }
        if let redirectReason {
            body["redirected"] = .bool(true)
            body["reason"] = .string(redirectReason)
        }
        return DaemonResponse.success(.object(body), generation: generation)
    }
}

final class LaunchLogWriter {
    private let handle: FileHandle?
    private let lock = NSLock()

    init(url: URL, errorLog: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        do {
            let h = try FileHandle(forWritingTo: url)
            h.seekToEndOfFile()
            self.handle = h
        } catch {
            DaemonLog.append(
                "launch-log-open-failed: \(error.localizedDescription)",
                to: errorLog)
            self.handle = nil
        }
    }

    func write(_ data: Data) {
        lock.lock()
        handle?.write(data)
        lock.unlock()
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        write(data)
    }

    func close() {
        guard let handle else { return }
        do {
            try handle.close()
        } catch {
            fputs("launch-log-close: \(error.localizedDescription)\n", stderr)
        }
    }
}
