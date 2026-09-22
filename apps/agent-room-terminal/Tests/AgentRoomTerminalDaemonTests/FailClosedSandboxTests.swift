import XCTest
@testable import AgentRoomTerminalCore
@testable import AgentRoomTerminalDaemon

final class FailClosedSandboxTests: XCTestCase {
    func testExecRunnerRejectsMissingSeatbeltProfileSync() {
        let run = ExecRunner.run(
            argv: ["/bin/echo", "hello"],
            roomDir: NSTemporaryDirectory(),
            env: [:],
            seatbeltProfile: nil,
            timeoutSeconds: 5
        )
        XCTAssertEqual(run.exitCode, 126, "프로파일이 없을 때 126(실행 거부)이어야 함")
        XCTAssertTrue(run.stderr.contains("Fail-Closed"), "에러 메시지에 Fail-Closed가 명시되어야 함")
        XCTAssertEqual(run.stdout, "")
    }

    func testExecRunnerRejectsEmptySeatbeltProfileStreaming() {
        var streamedData = Data()
        let run = ExecRunner.runStreaming(
            argv: ["/bin/echo", "hello"],
            roomDir: NSTemporaryDirectory(),
            env: [:],
            seatbeltProfile: "",
            timeoutSeconds: 5,
            onOutput: { streamedData.append($0) }
        )
        XCTAssertEqual(run.exitCode, 126, "빈 프로파일 스트리밍 시 126이어야 함")
        XCTAssertTrue(run.stderr.contains("Fail-Closed"))
        XCTAssertTrue(streamedData.isEmpty, "출력 스트림이 비어 있어야 함")
    }
}
