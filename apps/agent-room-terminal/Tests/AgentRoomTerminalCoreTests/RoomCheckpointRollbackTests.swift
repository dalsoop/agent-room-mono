import XCTest
@testable import AgentRoomTerminalCore

final class RoomCheckpointRollbackTests: XCTestCase {
    var tempRoomURL: URL?

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-checkpoint-test-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoomURL = url
    }

    override func tearDownWithError() throws {
        if let url = tempRoomURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCreateCheckpointAndRollback() throws {
        guard let roomURL = tempRoomURL else {
            XCTFail("tempRoomURL is nil")
            return
        }
        let manager = RoomCheckpointManager()
        let workURL = manager.workDirectory(in: roomURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        // 1. work/ 에 초기 파일 생성
        let file1URL = workURL.appendingPathComponent("file1.txt")
        let subDir = workURL.appendingPathComponent("sub", isDirectory: true)
        let file2URL = subDir.appendingPathComponent("file2.txt")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        try "initial content 1".write(to: file1URL, atomically: true, encoding: .utf8)
        try "initial content 2".write(to: file2URL, atomically: true, encoding: .utf8)

        // 2. 체크포인트 1 생성
        let ckpt1 = try manager.createCheckpoint(roomURL: roomURL, checkpointID: "ckpt-v1", description: "initial state")
        XCTAssertEqual(ckpt1.id, "ckpt-v1")
        XCTAssertEqual(ckpt1.fileCount, 2)
        XCTAssertNotNil(ckpt1.manifest["file1.txt"])
        XCTAssertNotNil(ckpt1.manifest["sub/file2.txt"])

        // 3. 파일 수정 및 신규 파일 생성
        try "modified content 1".write(to: file1URL, atomically: true, encoding: .utf8)
        let file3URL = workURL.appendingPathComponent("file3.txt")
        try "new file 3".write(to: file3URL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try String(contentsOf: file1URL, encoding: .utf8), "modified content 1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file3URL.path))

        // 4. 체크포인트 1로 롤백 수행
        try manager.rollback(roomURL: roomURL, to: "ckpt-v1")

        // 5. 검증: file1.txt 는 원래 내용으로 복원, file3.txt 는 삭제됨
        let restoredContent1 = try String(contentsOf: file1URL, encoding: .utf8)
        XCTAssertEqual(restoredContent1, "initial content 1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file3URL.path), "롤백 후 추가된 파일은 사라져야 함")

        let restoredContent2 = try String(contentsOf: file2URL, encoding: .utf8)
        XCTAssertEqual(restoredContent2, "initial content 2")
    }

    func testGuardedRunnerRollsBackOnFailureAndPreservesEvidence() throws {
        guard let roomURL = tempRoomURL else {
            XCTFail("tempRoomURL is nil")
            return
        }
        let manager = RoomCheckpointManager()
        let runner = RoomGuardedRunner(checkpointManager: manager)
        let workURL = manager.workDirectory(in: roomURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let codeURL = workURL.appendingPathComponent("main.swift")
        try "print(\"hello\")".write(to: codeURL, atomically: true, encoding: .utf8)

        let evidence = try runner.execute(
            roomURL: roomURL,
            argv: ["swift", "test"],
            runID: "test-run-fail"
        ) {
            try "broken syntax".write(to: codeURL, atomically: true, encoding: .utf8)
            return RoomExecutionResult(stdout: "Compiling...", stderr: "Syntax Error at line 1", exitCode: 1, violations: [])
        }

        XCTAssertEqual(evidence.verdict, .failed)
        XCTAssertTrue(evidence.rolledBack)

        let contentAfterRollback = try String(contentsOf: codeURL, encoding: .utf8)
        XCTAssertEqual(contentAfterRollback, "print(\"hello\")")

        let runDir = runner.runsDirectory(in: roomURL).appendingPathComponent("test-run-fail")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.appendingPathComponent("meta.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.appendingPathComponent("stderr.log").path))
        let stderrSaved = try String(contentsOf: runDir.appendingPathComponent("stderr.log"), encoding: .utf8)
        XCTAssertEqual(stderrSaved, "Syntax Error at line 1")
    }

    func testGuardedRunnerRollsBackOnPolicyViolation() throws {
        guard let roomURL = tempRoomURL else {
            XCTFail("tempRoomURL is nil")
            return
        }
        let manager = RoomCheckpointManager()
        let runner = RoomGuardedRunner(checkpointManager: manager)
        let workURL = manager.workDirectory(in: roomURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let fileURL = workURL.appendingPathComponent("config.json")
        try "{\"ok\": true}".write(to: fileURL, atomically: true, encoding: .utf8)

        let evidence = try runner.execute(
            roomURL: roomURL,
            argv: ["worker", "step"],
            runID: "test-run-violation"
        ) {
            try "{\"hacked\": true}".write(to: fileURL, atomically: true, encoding: .utf8)
            return RoomExecutionResult(stdout: "ok", stderr: "", exitCode: 0, violations: ["write outside tenant boundary"])
        }

        XCTAssertEqual(evidence.verdict, .policyViolated)
        XCTAssertTrue(evidence.rolledBack)

        let restored = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(restored, "{\"ok\": true}")
    }

    func testGuardedRunnerPreservesEvidenceOnSuccess() throws {
        guard let roomURL = tempRoomURL else {
            XCTFail("tempRoomURL is nil")
            return
        }
        let manager = RoomCheckpointManager()
        let runner = RoomGuardedRunner(checkpointManager: manager)
        let workURL = manager.workDirectory(in: roomURL)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let testFileURL = workURL.appendingPathComponent("feature.txt")
        try "v1".write(to: testFileURL, atomically: true, encoding: .utf8)

        let evidence = try runner.execute(
            roomURL: roomURL,
            argv: ["app", "compile"],
            runID: "test-run-success",
            verifyHook: {
                ["testSuitePassed", "coverage80Percent"]
            }
        ) {
            try "v2".write(to: testFileURL, atomically: true, encoding: .utf8)
            return RoomExecutionResult(stdout: "Build succeeded", stderr: "", exitCode: 0, violations: [])
        }

        XCTAssertEqual(evidence.verdict, .passed)
        XCTAssertFalse(evidence.rolledBack)

        let restored = try String(contentsOf: testFileURL, encoding: .utf8)
        XCTAssertEqual(restored, "v2")
    }
}
