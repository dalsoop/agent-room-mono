import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class AgentCredentialInjectorTests: XCTestCase {
    func testUnseedRemovesOnlyCredentialFile() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "credential-unseed-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"accessToken":"test-not-a-secret"}"#.utf8).write(to: file)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertTrue(fm.fileExists(atPath: dir.path))

        // 전사(projects/)는 증거라 남아야 한다 — 자격증명 파일만 사라진다.
        let projects = dir.appendingPathComponent("projects/slug", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: projects.appendingPathComponent("s.jsonl"))

        XCTAssertTrue(AgentCredentialInjector.unseed(tool: .claude, roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertTrue(fm.fileExists(atPath: projects.appendingPathComponent("s.jsonl").path))
        XCTAssertTrue(AgentCredentialInjector.unseed(tool: .claude, roomURL: room))
    }

    func testUnseedAllCleansCredentials() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "credential-unseed-all-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"token":"test-token"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        XCTAssertTrue(AgentCredentialInjector.unseedAll(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }

    func testWipeRemovesCredentials() throws {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "credential-wipe-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: room) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"secret":"keychain-copy"}"#.utf8).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        XCTAssertTrue(AgentCredentialInjector.wipe(roomURL: room))
        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }
}
