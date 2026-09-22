import CommandKit
import Darwin
import Foundation
import XCTest
@testable import AgentRoomTerminalCore
@testable import AgentRoomTerminalDaemon

final class DaemonTestHarness {
    let root: URL
    let logURL: URL
    let server: DaemonServer
    var client: DaemonClient
    private var stopped = false

    static func shortTempRoot() -> URL {
        URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("art-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    static func make(
        idleSeconds: TimeInterval,
        clock: DaemonClock = SystemDaemonClock(),
        authority: String? = nil
    ) throws -> DaemonTestHarness {
        let root = shortTempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let socket = root.appendingPathComponent("s.sock")
        let generation = root.appendingPathComponent("gen")
        let logURL = root.appendingPathComponent("daemon.log")
        let sessionsURL = root.appendingPathComponent("sessions.json")
        let server = DaemonServer(
            socketURL: socket,
            generationURL: generation,
            clock: clock,
            tuning: DaemonTuning(idleSeconds: idleSeconds),
            logURL: logURL,
            sessionsURL: sessionsURL
        )
        try server.start()
        let client = DaemonClient(
            socketURL: socket,
            spawnIfMissing: false,
            authority: authority
        )
        return DaemonTestHarness(root: root, logURL: logURL, server: server, client: client)
    }

    init(root: URL, logURL: URL, server: DaemonServer, client: DaemonClient) {
        self.root = root
        self.logURL = logURL
        self.server = server
        self.client = client
    }

    deinit {
        stop()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        server.stop()
        DaemonProcessReaper.reapDaemons(root: root)
        try? FileManager.default.removeItem(at: root)
    }

    func makeRoom() throws -> RoomFixture {
        let room = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: room, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: room.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        let envFile = room.appendingPathComponent("env")
        let pathValue = "/usr/bin:/bin:/usr/sbin:/sbin"
        let body = "PATH=\(pathValue)\nHOME=\(room.path)\n"
        try body.write(to: envFile, atomically: true, encoding: .utf8)
        return RoomFixture(path: room.path, envFile: envFile)
    }

    func makeChild(of parent: RoomFixture) throws -> RoomFixture {
        let children = URL(fileURLWithPath: parent.path).appendingPathComponent("children", isDirectory: true)
        let room = children.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: room, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: room.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        let envFile = room.appendingPathComponent("env")
        let pathValue = "/usr/bin:/bin:/usr/sbin:/sbin"
        let body = "PATH=\(pathValue)\nHOME=\(room.path)\n"
        try body.write(to: envFile, atomically: true, encoding: .utf8)
        return RoomFixture(path: room.path, envFile: envFile)
    }

    func snapshotText(sessionID: String) -> String {
        let response = server.handle(commandRoom(.snapshot(sessionID: sessionID, lines: 80)))
        let lines = response.result?["lines"]?.array ?? []
        return lines.compactMap(\.string).joined(separator: "\n")
    }

    func waitForSnapshot(sessionID: String, containing needle: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if snapshotText(sessionID: sessionID).lowercased().contains(needle.lowercased()) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}

struct RoomFixture {
    var path: String
    var envFile: URL
}

func commandRoom(_ req: DaemonRequest) -> DaemonRequest {
    var copy = req
    copy.authority = SessionAuthorizer.commandRoomAuthority
    return copy
}

final class DaemonZombieTests: XCTestCase {
    func testNoDaemonZombiesAfterTestSuite() throws {
        let result = CommandKitSync.run(
            "/usr/bin/pgrep",
            ["-f", "agent-room-terminal-daemon --socket /tmp/art-"],
            timeout: 5
        )
        XCTAssertEqual(
            result.exitCode, 1,
            "leaked daemon processes: \(result.stdout)"
        )
    }
}
