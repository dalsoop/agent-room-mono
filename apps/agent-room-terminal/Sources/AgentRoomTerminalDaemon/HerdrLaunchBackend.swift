import Darwin
import Foundation
import InteropKit
import AgentRoomTerminalCore
import CommandKit

// MARK: - herdr CLI 러너 계약

/// herdr CLI 호출 추상화. 테스트는 이 러너를 주입해 argv 시퀀스만 검증한다.
protocol HerdrCLIRunning {
    func run(_ argv: [String], timeoutSeconds: Int) -> HerdrCLIOutcome
}

struct HerdrCLIOutcome {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

/// 실 프로세스 러너 — herdr 바이너리를 직접 실행한다.
final class ProcessHerdrRunner: HerdrCLIRunning {
    private let herdrPath: String

    init(herdrPath: String = HostPlatform.cliBinPath("herdr")) {
        self.herdrPath = herdrPath
    }

    func run(_ argv: [String], timeoutSeconds: Int) -> HerdrCLIOutcome {
        let safeResult = SafeProcessRunner.run(
            herdrPath,
            actualArgs
        )
        } catch {
            return HerdrCLIOutcome(
                exitCode: 127, stdout: "", stderr: error.localizedDescription)
        }
        var pipeCloseFailure: String?
        do {
            try outPipe.fileHandleForWriting.close()
        } catch {
            pipeCloseFailure = error.localizedDescription
        }
        do {
            try errPipe.fileHandleForWriting.close()
        } catch {
            pipeCloseFailure = error.localizedDescription
        }
        _ = pipeCloseFailure
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while proc.isRunning && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        if proc.isRunning {
            kill(-proc.processIdentifier, SIGTERM)
            let killDeadline = Date().addingTimeInterval(1)
            while proc.isRunning && Date() < killDeadline {
                CFRunLoopRunInMode(.defaultMode, 0.05, true)
            }
            if proc.isRunning {
                kill(-proc.processIdentifier, SIGKILL)
                while proc.isRunning {
                    CFRunLoopRunInMode(.defaultMode, 0.01, true)
                }
            }
        }
        let stdout = String(
            decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(
            decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return HerdrCLIOutcome(
            exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

// MARK: - herdr 기동 백엔드

enum HerdrLaunchError: Error, LocalizedError {
    case tabCreateFailed(exitCode: Int32, detail: String)
    case paneIDUnparsable(String)
    case paneRunFailed(paneID: String, exitCode: Int32, detail: String)

    var errorDescription: String? {
        switch self {
        case .tabCreateFailed(let code, let detail):
            return "herdr tab create failed (exit \(code)): \(detail)"
        case .paneIDUnparsable(let stdout):
            return "herdr tab create output has no pane id: \(stdout.prefix(200))"
        case .paneRunFailed(let paneID, let code, let detail):
            return "herdr pane run \(paneID) failed (exit \(code)): \(detail)"
        }
    }
}

/// herdr 가 PTY 를 소유하는 opt-in 기동 백엔드.
/// 1) `herdr tab create --cwd <room workdir> --env ROOM_ID=<uuid> --label <roomID 접두>`
/// 2) create 출력 JSON(`result.root_pane.pane_id`)에서 새 pane id 획득 — 세션 id 대용
/// 3) `herdr pane run <PANE_ID> <agent command…>` 로 에이전트 기동
/// 실패 시 pty 로 폴백하지 않고 오류로 끝낸다. attach 경로는 아직 연결돼 있지 않다.
final class HerdrLaunchBackend: RoomAgentLaunching {
    let name = "herdr"
    private let runner: HerdrCLIRunning

    init(runner: HerdrCLIRunning = ProcessHerdrRunner()) {
        self.runner = runner
    }

    func launch(_ command: RoomAgentLaunchCommand) throws -> RoomAgentLaunchResult {
        let label = String(command.roomID.prefix(8))
        var createArgv = [
            "herdr", "tab", "create",
            "--cwd", command.roomDir,
        ]
        var envVars = command.env
        envVars["ROOM_ID"] = envVars["ROOM_ID"] ?? command.roomID
        for (k, v) in envVars.sorted(by: { $0.key < $1.key }) {
            createArgv.append(contentsOf: ["--env", "\(k)=\(v)"])
        }
        createArgv.append(contentsOf: ["--label", label])

        let create = runner.run(createArgv, timeoutSeconds: command.timeoutSeconds)
        guard create.exitCode == 0 else {
            throw HerdrLaunchError.tabCreateFailed(
                exitCode: create.exitCode,
                detail: create.stderr.isEmpty ? create.stdout : create.stderr)
        }
        let tabID = Self.parseTabID(create.stdout)
        guard let paneID = Self.parseRootPaneID(create.stdout) else {
            if let tabID {
                _ = runner.run(["herdr", "tab", "close", tabID], timeoutSeconds: command.timeoutSeconds)
            }
            throw HerdrLaunchError.paneIDUnparsable(create.stdout)
        }

        let sessionID = "exec-herdr-\(paneID)"
        command.onStarted(sessionID)

        var runArgv = ["herdr", "pane", "run", paneID]
        if let seatbeltProfile = command.seatbeltProfile, !seatbeltProfile.isEmpty {
            runArgv.append(contentsOf: [AppPaths.sandboxExec, "-p", seatbeltProfile])
        }
        runArgv.append(contentsOf: command.argv)

        let runOutcome = runner.run(
            runArgv,
            timeoutSeconds: command.timeoutSeconds)
        guard runOutcome.exitCode == 0 else {
            _ = runner.run(["herdr", "pane", "close", paneID], timeoutSeconds: command.timeoutSeconds)
            throw HerdrLaunchError.paneRunFailed(
                paneID: paneID,
                exitCode: runOutcome.exitCode,
                detail: runOutcome.stderr.isEmpty ? runOutcome.stdout : runOutcome.stderr)
        }
        return RoomAgentLaunchResult(
            sessionID: sessionID,
            run: ExecRunner.Run(
                stdout: runOutcome.stdout,
                stderr: runOutcome.stderr,
                exitCode: runOutcome.exitCode,
                timedOut: false))
    }

    /// `herdr tab create` 출력(JSON)에서 `result.root_pane.pane_id`를 꺼낸다.
    static func parseRootPaneID(_ output: String) -> String? {
        guard let data = output.data(using: .utf8) else { return nil }
        let json: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            json = decoded
        } catch {
            return nil
        }
        guard let result = json["result"] as? [String: Any],
              let rootPane = result["root_pane"] as? [String: Any],
              let paneID = rootPane["pane_id"] as? String,
              !paneID.isEmpty
        else { return nil }
        return paneID
    }

    /// `herdr tab create` 출력(JSON)에서 `result.tab.tab_id`를 꺼낸다.
    static func parseTabID(_ output: String) -> String? {
        guard let data = output.data(using: .utf8) else { return nil }
        let decoded: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            decoded = obj
        } catch {
            return nil
        }
        guard let result = decoded["result"] as? [String: Any],
              let tab = result["tab"] as? [String: Any],
              let tabID = tab["tab_id"] as? String,
              !tabID.isEmpty
        else { return nil }
        return tabID
    }
}
