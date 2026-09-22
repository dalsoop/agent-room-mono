import Darwin
import Foundation
import XCTest
@testable import AgentRoomTerminalCore
@testable import AgentRoomTerminalDaemon

final class SessionTablePersistenceTests: XCTestCase {
    var scratch: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-table-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        DaemonProcessReaper.reapAllTestDaemons()
        try FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    func testPersistsLiveSessionAndRestoresAsRecovered() throws {
        let file = scratch.appendingPathComponent("sessions.json")
        let room = try makeRoom()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }
        XCTAssertTrue(ProcessGroupProbe.isAlive(pgid: sleeper.processIdentifier))

        let live = PtyTerminalSession(
            recovered: PersistedSessionRecord(
                sessionID: "sess-live",
                roomDir: room.path,
                pgid: sleeper.processIdentifier,
                shell: "zsh -r",
                startedAt: PersistedSessionRecord.formatDate(Date(timeIntervalSince1970: 1_700_000_000))
            ),
            ringLines: 8
        )
        let writer = SessionTable(fileURL: file, ringLines: 8)
        writer.add(live)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        let reader = SessionTable(fileURL: file, ringLines: 8)
        try reader.restore()
        XCTAssertEqual(reader.count, 1)
        let restored = try XCTUnwrap(reader.get("sess-live"))
        XCTAssertTrue(restored.recovered)
        XCTAssertEqual(restored.pgid, sleeper.processIdentifier)
        XCTAssertEqual(restored.roomDir, room.path)
        XCTAssertEqual(restored.shell, "zsh -r")

        let listed = listSessions(from: reader)
        XCTAssertEqual(listed?["recovered"]?.bool, true)
        XCTAssertEqual(listed?["sessionID"]?.string, "sess-live")
    }

    func testTwoSessionsSameRoomPersist() throws {
        let file = scratch.appendingPathComponent("sessions.json")
        let room = try makeRoom()
        let predProc = Process()
        predProc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        predProc.arguments = ["30"]
        try predProc.run()
        let succProc = Process()
        succProc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        succProc.arguments = ["30"]
        try succProc.run()
        defer {
            predProc.terminate()
            succProc.terminate()
            predProc.waitUntilExit()
            succProc.waitUntilExit()
        }
        let table = SessionTable(fileURL: file, ringLines: 8)
        table.add(PtyTerminalSession(
            recovered: PersistedSessionRecord(
                sessionID: "sess-pred",
                roomDir: room.path,
                pgid: predProc.processIdentifier,
                shell: "zsh -r",
                startedAt: PersistedSessionRecord.formatDate(Date()),
                sessionRole: RoomSessionRole.predecessor.rawValue
            ),
            ringLines: 8
        ))
        table.add(PtyTerminalSession(
            recovered: PersistedSessionRecord(
                sessionID: "sess-succ",
                roomDir: room.path,
                pgid: succProc.processIdentifier,
                shell: "zsh -r",
                startedAt: PersistedSessionRecord.formatDate(Date()),
                sessionRole: RoomSessionRole.successor.rawValue
            ),
            ringLines: 8
        ))
        XCTAssertEqual(table.sessions(inRoom: room.path).count, 2)
        let reader = SessionTable(fileURL: file, ringLines: 8)
        try reader.restore()
        XCTAssertEqual(reader.count, 2)
        XCTAssertEqual(reader.get("sess-pred")?.sessionRole, "predecessor")
        XCTAssertEqual(reader.get("sess-succ")?.sessionRole, "successor")
        XCTAssertEqual(reader.sessions(inRoom: room.path).count, 2)
    }

    func testDeadPgidIsDroppedAndLogged() throws {
        let file = scratch.appendingPathComponent("sessions.json")
        let room = try makeRoom()
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        XCTAssertFalse(ProcessGroupProbe.isAlive(pgid: dead.processIdentifier))

        let record = PersistedSessionRecord(
            sessionID: "sess-dead",
            roomDir: room.path,
            pgid: dead.processIdentifier,
            shell: "zsh",
            startedAt: PersistedSessionRecord.formatDate(Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(PersistedSessionFile(sessions: [record])).write(to: file)

        let table = SessionTable(fileURL: file, ringLines: 8)
        try table.restore()
        XCTAssertEqual(table.count, 0)
        XCTAssertNil(table.get("sess-dead"))

        let log = room.appendingPathComponent("state/term.log")
        let text = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(text.contains("recovered-dead"), text)

        let leftover = try JSONDecoder().decode(PersistedSessionFile.self, from: Data(contentsOf: file))
        XCTAssertEqual(leftover.sessions, [])
    }

    func testRecoveredSessionRejectsAttach() throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("art-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let room = try makeRoom()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }
        let sessionsURL = root.appendingPathComponent("sessions.json")
        let record = PersistedSessionRecord(
            sessionID: "sess-rec",
            roomDir: room.path,
            pgid: sleeper.processIdentifier,
            shell: "zsh -r",
            startedAt: PersistedSessionRecord.formatDate(Date())
        )
        try JSONEncoder().encode(PersistedSessionFile(sessions: [record])).write(to: sessionsURL)

        let server = DaemonServer(
            socketURL: root.appendingPathComponent("s.sock"),
            generationURL: root.appendingPathComponent("gen"),
            tuning: DaemonTuning(idleSeconds: 3600),
            sessionsURL: sessionsURL
        )
        try server.start()
        defer { server.stop() }

        var list = DaemonRequest.listSessions()
        list.authority = SessionAuthorizer.commandRoomAuthority
        let listed = server.handle(list)
        XCTAssertTrue(listed.ok, listed.error ?? "")
        let session = listed.result?["sessions"]?.array?.first
        XCTAssertEqual(session?["recovered"]?.bool, true)

        var attach = DaemonRequest.attach(sessionID: "sess-rec", lines: 10)
        attach.authority = SessionAuthorizer.commandRoomAuthority
        let attached = server.handle(attach)
        XCTAssertFalse(attached.ok)
        XCTAssertEqual(attached.error, "session recovered, attach unavailable")
    }

    func testCloseDeadRecoveredSessionKeepsExitZero() throws {
        let room = try makeRoom()
        let dead = Process()
        dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try dead.run()
        dead.waitUntilExit()
        let session = PtyTerminalSession(
            recovered: PersistedSessionRecord(
                sessionID: "sess-dead-close",
                roomDir: room.path,
                pgid: dead.processIdentifier,
                shell: "zsh",
                startedAt: PersistedSessionRecord.formatDate(Date())
            ),
            ringLines: 8
        )
        session.close(grace: 0)
        XCTAssertEqual(session.recordedExitCode, 0)
        XCTAssertTrue(session.hasExited)
    }

    private func makeRoom() throws -> URL {
        let room = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: room.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        return room
    }

    private func listSessions(from table: SessionTable) -> [String: JSONValue]? {
        table.all().first.map { session in
            [
                "sessionID": .string(session.sessionID),
                "roomDir": .string(session.roomDir),
                "pgid": .int(Int(session.pgid)),
                "recovered": .bool(session.recovered),
            ]
        }
    }
}
