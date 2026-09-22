import Foundation
import XCTest
@testable import AgentRoomTerminalDaemon

/// 주입 러너 — 호출된 argv 시퀀스를 기록하고 미리 준비한 결과를 차례로 돌려준다.
final class RecordingHerdrRunner: HerdrCLIRunning {
    private(set) var calls: [[String]] = []
    private let outcomes: [HerdrCLIOutcome]
    private let lock = NSLock()

    init(outcomes: [HerdrCLIOutcome]) {
        self.outcomes = outcomes
    }

    func run(_ argv: [String], timeoutSeconds: Int) -> HerdrCLIOutcome {
        lock.lock()
        calls.append(argv)
        let index = calls.count - 1
        lock.unlock()
        return index < outcomes.count
            ? outcomes[index]
            : HerdrCLIOutcome(exitCode: 0, stdout: "", stderr: "")
    }
}

private func makeCommand(
    roomDir: String = "/tmp/rooms/room-1234abcd",
    argv: [String] = ["claude", "--print", "hi"],
    onStarted: @escaping (String) -> Void = { _ in }
) -> RoomAgentLaunchCommand {
    RoomAgentLaunchCommand(
        argv: argv,
        roomDir: roomDir,
        roomID: "room-1234abcd5678",
        env: ["ROOM_TOOL": "claude"],
        seatbeltProfile: nil,
        timeoutSeconds: 30,
        onOutput: { _ in },
        onStarted: onStarted)
}

private let createJSON = """
    {"id":"cli:tab:create","result":{"root_pane":{"pane_id":"w6:pX","cwd":"/tmp"},"tab":{"tab_id":"w6:t4"},"type":"tab_created"}}
    """

final class HerdrLaunchBackendTests: XCTestCase {
    func testLaunchRunsTabCreateThenPaneRunSequence() throws {
        let runner = RecordingHerdrRunner(outcomes: [
            HerdrCLIOutcome(exitCode: 0, stdout: createJSON, stderr: ""),
            HerdrCLIOutcome(exitCode: 0, stdout: "started", stderr: ""),
        ])
        let backend = HerdrLaunchBackend(runner: runner)
        var started: [String] = []
        let result = try backend.launch(makeCommand {
            started.append($0)
        })

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0], [
            "herdr", "tab", "create",
            "--cwd", "/tmp/rooms/room-1234abcd",
            "--env", "ROOM_ID=room-1234abcd5678",
            "--env", "ROOM_TOOL=claude",
            "--label", "room-123",
        ])
        XCTAssertEqual(
            runner.calls[1],
            ["herdr", "pane", "run", "w6:pX", "claude", "--print", "hi"])
        XCTAssertEqual(result.sessionID, "exec-herdr-w6:pX")
        XCTAssertEqual(result.run.exitCode, 0)
        XCTAssertEqual(started, ["exec-herdr-w6:pX"])
    }

    func testLaunchWithSeatbeltWrapsCommandInSandboxExec() throws {
        let runner = RecordingHerdrRunner(outcomes: [
            HerdrCLIOutcome(exitCode: 0, stdout: createJSON, stderr: ""),
            HerdrCLIOutcome(exitCode: 0, stdout: "started", stderr: ""),
        ])
        let backend = HerdrLaunchBackend(runner: runner)
        var cmd = makeCommand()
        cmd.seatbeltProfile = "(version 1)(deny default)"
        let result = try backend.launch(cmd)

        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(
            runner.calls[1],
            ["herdr", "pane", "run", "w6:pX", "/usr/bin/sandbox-exec", "-p", "(version 1)(deny default)", "claude", "--print", "hi"])
        XCTAssertEqual(result.sessionID, "exec-herdr-w6:pX")
    }

    func testTabCreateFailureThrowsWithoutFallbackOrPaneRun() throws {
        let runner = RecordingHerdrRunner(outcomes: [
            HerdrCLIOutcome(exitCode: 3, stdout: "", stderr: "no server"),
        ])
        let backend = HerdrLaunchBackend(runner: runner)
        var startedCount = 0

        XCTAssertThrowsError(try backend.launch(makeCommand { _ in startedCount += 1 })) { error in
            guard case HerdrLaunchError.tabCreateFailed(let code, _) = error else {
                return XCTFail("expected tabCreateFailed, got \(error)")
            }
            XCTAssertEqual(code, 3)
        }
        // 폴백 금지 — pane run 이나 그 이후 호출이 없어야 한다.
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(startedCount, 0)
    }

    func testUnparsableCreateOutputThrowsPaneIDUnparsable() throws {
        let runner = RecordingHerdrRunner(outcomes: [
            HerdrCLIOutcome(exitCode: 0, stdout: "not json", stderr: ""),
        ])
        let backend = HerdrLaunchBackend(runner: runner)

        XCTAssertThrowsError(try backend.launch(makeCommand())) { error in
            guard case HerdrLaunchError.paneIDUnparsable = error else {
                return XCTFail("expected paneIDUnparsable, got \(error)")
            }
        }
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testPaneRunFailureThrowsAfterSessionStarted() throws {
        let runner = RecordingHerdrRunner(outcomes: [
            HerdrCLIOutcome(exitCode: 0, stdout: createJSON, stderr: ""),
            HerdrCLIOutcome(exitCode: 5, stdout: "", stderr: "agent died"),
        ])
        let backend = HerdrLaunchBackend(runner: runner)
        var started: [String] = []

        XCTAssertThrowsError(try backend.launch(makeCommand {
            started.append($0)
        })) { error in
            guard case HerdrLaunchError.paneRunFailed(let paneID, let code, _) = error else {
                return XCTFail("expected paneRunFailed, got \(error)")
            }
            XCTAssertEqual(paneID, "w6:pX")
            XCTAssertEqual(code, 5)
        }
        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertEqual(runner.calls[2], ["herdr", "pane", "close", "w6:pX"])
        XCTAssertEqual(started, ["exec-herdr-w6:pX"])
    }

    func testUnparsablePaneIDWithValidTabRollsBackTab() throws {
        let tabOnlyJSON = """
            {"id":"cli:tab:create","result":{"tab":{"tab_id":"w6:t4"},"type":"tab_created"}}
            """
        let runner = RecordingHerdrRunner(outcomes: [
            HerdrCLIOutcome(exitCode: 0, stdout: tabOnlyJSON, stderr: ""),
        ])
        let backend = HerdrLaunchBackend(runner: runner)

        XCTAssertThrowsError(try backend.launch(makeCommand())) { error in
            guard case HerdrLaunchError.paneIDUnparsable = error else {
                return XCTFail("expected paneIDUnparsable, got \(error)")
            }
        }
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1], ["herdr", "tab", "close", "w6:t4"])
    }

    func testParseRootPaneID() {
        XCTAssertEqual(HerdrLaunchBackend.parseRootPaneID(createJSON), "w6:pX")
        XCTAssertNil(HerdrLaunchBackend.parseRootPaneID("{}"))
        XCTAssertNil(HerdrLaunchBackend.parseRootPaneID(""))
        XCTAssertNil(
            HerdrLaunchBackend.parseRootPaneID(
                #"{"result":{"root_pane":{"pane_id":""}}}"#))
    }

    func testParseTabID() {
        XCTAssertEqual(HerdrLaunchBackend.parseTabID(createJSON), "w6:t4")
        XCTAssertNil(HerdrLaunchBackend.parseTabID("{}"))
        XCTAssertNil(HerdrLaunchBackend.parseTabID(""))
        XCTAssertNil(
            HerdrLaunchBackend.parseTabID(
                #"{"result":{"tab":{"tab_id":""}}}"#))
    }
}

final class LaunchBackendFactoryTests: XCTestCase {
    func testDefaultIsPtyWhenUnset() {
        let backend = LaunchBackendFactory.resolve(environment: [:])
        XCTAssertEqual(backend.name, "pty")
        XCTAssertTrue(backend is PtyExecLaunchBackend)
    }

    func testUnknownValuesStayPtyAndMatchIsCaseInsensitive() {
        XCTAssertEqual(
            LaunchBackendFactory.resolve(environment: ["AGENT_ROOM_LAUNCH_BACKEND": "bogus"]).name,
            "pty")
        XCTAssertEqual(
            LaunchBackendFactory.resolve(environment: ["AGENT_ROOM_LAUNCH_BACKEND": "HERDR"]).name,
            "herdr")
    }

    func testHerdrOptInSelectsHerdrBackend() {
        let backend = LaunchBackendFactory.resolve(
            environment: ["AGENT_ROOM_LAUNCH_BACKEND": "herdr"])
        XCTAssertEqual(backend.name, "herdr")
        XCTAssertTrue(backend is HerdrLaunchBackend)
    }
}
