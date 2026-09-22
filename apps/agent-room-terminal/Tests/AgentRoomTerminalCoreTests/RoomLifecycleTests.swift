import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class RoomLifecycleTests: XCTestCase {
    override func tearDown() {
        DaemonProcessReaper.reapAllTestDaemons()
        super.tearDown()
    }

    func testRoomLifecycleCloseWipesCredentials() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "lifecycle-close-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"token":"lifecycle-close-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        XCTAssertTrue(RoomLifecycle.close(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }

    func testRoomLifecycleVacateWipesCredentials() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "lifecycle-vacate-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"token":"lifecycle-vacate-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        XCTAssertTrue(RoomLifecycle.vacate(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }

    func testRoomLifecycleCleanupAndDismantle() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "lifecycle-cleanup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"token":"cleanup-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        XCTAssertTrue(RoomLifeCycle.cleanup(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))

        // 재시드 후 dismantle 검증
        try Data(#"{"token":"dismantle-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        XCTAssertTrue(RoomLifecycle.dismantle(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }

    func testRoomOperationsWipesOnCloseAndVacate() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "room-operations-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")

        // close via RoomOperations
        try Data(#"{"token":"ops-close-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
        XCTAssertTrue(RoomOperations.close(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))

        // vacate via RoomOperations
        try Data(#"{"token":"ops-vacate-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
        XCTAssertTrue(RoomOperations.vacate(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }
}
