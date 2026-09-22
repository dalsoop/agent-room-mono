import Darwin
import Foundation
import XCTest
@testable import AgentRoomTerminalCore
@testable import AgentRoomTerminalDaemon

final class DaemonRoomEventsTests: XCTestCase {
    override func tearDown() {
        DaemonProcessReaper.reapAllTestDaemons()
        super.tearDown()
    }

    func testDaemonSessionLifecycleEventsLogged() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let roomURL = URL(fileURLWithPath: room.path)
        let log = RoomEventLog(roomURL: roomURL)

        // 1. openSession -> sessionStarted 이벤트
        let openReq = commandRoom(
            .openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f")
        )
        let opened = try harness.client.send(openReq)
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        // 2. exec with verdict -> verdictRan 이벤트
        let execReq = commandRoom(
            .exec(sessionID: sessionID, roomDir: room.path, argv: ["echo", "verdict-result", "--verdict"])
        )
        let execRes = try harness.client.send(execReq)
        XCTAssertTrue(execRes.ok, execRes.error ?? "")

        // 3. closeSession -> sessionExited 및 closed 이벤트
        let closeReq = commandRoom(.closeSession(sessionID: sessionID))
        let closeRes = try harness.client.send(closeReq)
        XCTAssertTrue(closeRes.ok, closeRes.error ?? "")

        // 4. events.jsonl 검증
        let readResult = log.read(since: 0)
        XCTAssertEqual(readResult.corruptCount, 0)
        let kinds = readResult.events.map(\.kind)

        XCTAssertTrue(kinds.contains(RoomEventKind.sessionStarted), "must contain sessionStarted")
        XCTAssertTrue(kinds.contains(RoomEventKind.verdictRan), "must contain verdictRan")
        XCTAssertTrue(kinds.contains(RoomEventKind.sessionExited), "must contain sessionExited")
        XCTAssertTrue(kinds.contains(RoomEventKind.closed), "must contain closed")

        // seq 증가 무결성 확인
        let seqs = readResult.events.map(\.seq)
        XCTAssertEqual(seqs, Array(1...readResult.events.count), "seq must be sequential starting from 1")

        // 데몬 재기동 후 복구/새 세션도 중복 seq 없이 이어지는지 검증
        let lastSeq = seqs.last ?? 0
        let nextEvent = try log.append(RoomEvent(kind: RoomEventKind.created))
        XCTAssertEqual(nextEvent.seq, lastSeq + 1)
    }

    func testLaunchExecRecordsSessionStartedAndExited() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let roomURL = URL(fileURLWithPath: room.path)
        let log = RoomEventLog(roomURL: roomURL)

        let openReq = commandRoom(
            .openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f")
        )
        let opened = try harness.client.send(openReq)
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        let launchExec = commandRoom(
            .exec(sessionID: sessionID, roomDir: room.path, argv: ["echo", "hello"], launch: true)
        )
        let launchRes = try harness.client.send(launchExec)
        XCTAssertTrue(launchRes.ok, launchRes.error ?? "")

        let events = log.read(since: 0).events
        let kinds = events.map(\.kind)
        let sessionStartedEvents = events.filter { $0.kind == RoomEventKind.sessionStarted }
        XCTAssertEqual(sessionStartedEvents.count, 2, "PTY + exec sessionStarted")
        let execStarted = sessionStartedEvents.last
        let execSID = execStarted?.payload["sessionID"]?.string ?? ""
        XCTAssertTrue(execSID.hasPrefix("exec-"), "exec sessionID must start with exec-")

        let sessionExitedEvents = events.filter { $0.kind == RoomEventKind.sessionExited }
        XCTAssertEqual(sessionExitedEvents.count, 1, "exec sessionExited only")
        let exitedSID = sessionExitedEvents.first?.payload["sessionID"]?.string ?? ""
        XCTAssertEqual(exitedSID, execSID, "exited sessionID must match started")

        XCTAssertFalse(kinds.contains(RoomEventKind.verdictRan), "non-verdict exec must not record verdictRan")
    }

    func testNonLaunchExecDoesNotRecordSessionEvents() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let roomURL = URL(fileURLWithPath: room.path)
        let log = RoomEventLog(roomURL: roomURL)

        let openReq = commandRoom(
            .openSession(
                roomDir: room.path,
                envFile: room.envFile.path,
                shell: "zsh -f",
                seatbeltProfile: "(version 1)(allow default)"
            )
        )
        let opened = try harness.client.send(openReq)
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        let normalExec = commandRoom(
            .exec(sessionID: sessionID, roomDir: room.path, argv: ["echo", "hello"], raw: true)
        )
        let execRes = try harness.client.send(normalExec)
        XCTAssertTrue(execRes.ok, execRes.error ?? "")

        let events = log.read(since: 0).events
        let sessionStartedEvents = events.filter { $0.kind == RoomEventKind.sessionStarted }
        XCTAssertEqual(sessionStartedEvents.count, 1, "only PTY sessionStarted")
        XCTAssertEqual(events.filter({ $0.kind == RoomEventKind.sessionExited }).count, 0,
                       "non-launch exec must not record sessionExited")
    }

    func testCloseSessionWritesExactlyOneClosed() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let roomURL = URL(fileURLWithPath: room.path)
        let log = RoomEventLog(roomURL: roomURL)

        let openReq = commandRoom(
            .openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f")
        )
        let opened = try harness.client.send(openReq)
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        let closeReq = commandRoom(.closeSession(sessionID: sessionID))
        let closeRes = try harness.client.send(closeReq)
        XCTAssertTrue(closeRes.ok, closeRes.error ?? "")

        let events = log.read(since: 0).events
        let closedEvents = events.filter { $0.kind == RoomEventKind.closed }
        XCTAssertEqual(closedEvents.count, 1, "daemon closeSession must write exactly one closed event")
    }

    func testEventsStreamFollow() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let room = try harness.makeRoom()

        let collector = EventCollector()

        let subClient = DaemonClient(
            socketURL: harness.client.socketURL,
            spawnIfMissing: false,
            authority: SessionAuthorizer.commandRoomAuthority
        )

        let exp = expectation(description: "received sessionStarted and closed")
        let streamThread = Thread {
            do {
                try subClient.subscribeEvents(roomDir: room.path, since: 0) { event in
                    collector.append(event)
                    let kinds = collector.allEvents.map(\.kind)
                    if kinds.contains(RoomEventKind.sessionStarted) && kinds.contains(RoomEventKind.closed) {
                        exp.fulfill()
                    }
                }
            } catch {
                collector.setError(error)
            }
        }
        streamThread.start()

        // 스트림 연결 대기
        Thread.sleep(forTimeInterval: 0.1)

        // 세션 열기
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        // 세션 닫기
        let closed = try harness.client.send(
            commandRoom(.closeSession(sessionID: sessionID))
        )
        XCTAssertTrue(closed.ok, closed.error ?? "")

        wait(for: [exp], timeout: 5.0)

        let kinds = collector.allEvents.map(\.kind)
        XCTAssertNil(collector.lastError)
        XCTAssertTrue(kinds.contains(RoomEventKind.sessionStarted))
        XCTAssertTrue(kinds.contains(RoomEventKind.closed))
    }

    private func makeHarness() throws -> DaemonTestHarness {
        try DaemonTestHarness.make(
            idleSeconds: 3600,
            authority: SessionAuthorizer.commandRoomAuthority
        )
    }
}

private final class EventCollector {
    private let lock = NSLock()
    private var events: [RoomEvent] = []
    private var error: Error?

    func append(_ event: RoomEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func setError(_ err: Error) {
        lock.lock()
        error = err
        lock.unlock()
    }

    var allEvents: [RoomEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    var lastError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}
