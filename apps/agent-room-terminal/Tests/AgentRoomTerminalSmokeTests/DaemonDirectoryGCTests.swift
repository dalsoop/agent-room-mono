import Foundation
import XCTest
@testable import AgentRoomTerminalCore
@testable import AgentRoomTerminalCLI

final class DaemonDirectoryGCTests: XCTestCase {
    func testScanAndCleanupStaleDaemonDirectory() throws {
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gc-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        // 죽은 데몬 디렉터리 모의 생성 (art-dead-1)
        let deadDir = tempBase.appendingPathComponent("art-dead-1")
        try FileManager.default.createDirectory(at: deadDir, withIntermediateDirectories: true)
        let deadPid = deadDir.appendingPathComponent("daemon.pid")
        try "99999999".write(to: deadPid, atomically: true, encoding: .utf8) // 존재하지 않는 PID

        // 스캔 테스트
        let report = DaemonDirectoryGC.scan(tmpDir: tempBase.path)
        XCTAssertEqual(report.staleDirectories.count, 1)
        XCTAssertTrue(report.staleDirectories[0].contains("art-dead-1"))

        // 클린업 테스트 (dryRun: false)
        let cleaned = DaemonDirectoryGC.cleanup(dryRun: false, tmpDir: tempBase.path)
        XCTAssertEqual(cleaned.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deadDir.path), "죽은 디렉터리가 삭제되어야 함")
    }
}
