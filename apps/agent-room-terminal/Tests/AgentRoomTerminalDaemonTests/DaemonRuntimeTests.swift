import Darwin
import Foundation
import os
import XCTest
import SandboxKit
@testable import AgentRoomTerminalCore
@testable import AgentRoomTerminalDaemon

final class DaemonRuntimeTests: XCTestCase {
    override func tearDown() {
        DaemonProcessReaper.reapAllTestDaemons()
        super.tearDown()
    }

    func testSocketRoundTripOpenThenExecLs() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = opened.result?["sessionID"]?.string
        XCTAssertNotNil(sessionID)
        let exec = try harness.client.send(
            .exec(sessionID: sessionID, roomDir: room.path, argv: ["/bin/ls"])
        )
        XCTAssertTrue(exec.ok, exec.error ?? "")
        XCTAssertEqual(exec.result?["exitCode"]?.int, 0)
    }

    func testRestrictedZshRejectsAbsolutePath() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -r -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 2)
        _ = try harness.client.send(
            commandRoom(.input(sessionID: sessionID, text: "/usr/local/bin/true\r"))
        )
        let found = harness.waitForSnapshot(
            sessionID: sessionID,
            containing: "restricted",
            timeout: 5
        )
        let dump = harness.snapshotText(sessionID: sessionID)
        XCTAssertTrue(found, "expected restricted in snapshot, got: \(dump)")
    }

    func testIdleExitWithInjectedClock() throws {
        let clock = ManualDaemonClock()
        let harness = try DaemonTestHarness.make(idleSeconds: 60, clock: clock)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -r"))
        )
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = try harness.client.send(commandRoom(.closeSession(sessionID: sessionID)))
        clock.advance(61)
        XCTAssertTrue(harness.server.pollIdle())
    }

    func testForeignRoomSessionRejected() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let roomA = try harness.makeRoom()
        let roomB = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: roomA.path, envFile: roomA.envFile.path, shell: "zsh -r"))
        )
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        let exec = try harness.client.send(
            .exec(sessionID: sessionID, roomDir: roomB.path, argv: ["/bin/ls"])
        )
        XCTAssertFalse(exec.ok)
        XCTAssertEqual(exec.error, SessionAuthorizer.foreignRoomError)
    }

    func testGenerationIncreasesAcrossStarts() throws {
        let root = DaemonTestHarness.shortTempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            DaemonProcessReaper.reapDaemons(root: root)
            try? FileManager.default.removeItem(at: root)
        }
        let socket = root.appendingPathComponent("s.sock")
        let generation = root.appendingPathComponent("gen")
        let sessions = root.appendingPathComponent("sessions.json")
        let first = DaemonServer(
            socketURL: socket,
            generationURL: generation,
            tuning: DaemonTuning(idleSeconds: 3600),
            sessionsURL: sessions
        )
        try first.start()
        let gen1 = first.generation
        first.stop()
        let second = DaemonServer(
            socketURL: socket,
            generationURL: generation,
            tuning: DaemonTuning(idleSeconds: 3600),
            sessionsURL: sessions
        )
        try second.start()
        let gen2 = second.generation
        second.stop()
        XCTAssertGreaterThan(gen2, gen1)
        let listed = second.handle(commandRoom(.listSessions()))
        XCTAssertEqual(listed.generation, gen2)
        XCTAssertEqual(listed.result?["generation"]?.int, Int(gen2))
    }

    func testSeatbeltWriteOutsideRoom() throws {
        guard AppPaths.isSandboxAvailable else {
            throw XCTSkip("sandbox-exec not available")
        }
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let outside = URL(fileURLWithPath: "/var/tmp")
            .appendingPathComponent("agent-room-t6-\(UUID().uuidString)")
        let context = try SandboxContext.allocate(
            tenant: "test",
            roomID: "room-t6",
            homeDirectory: harness.root.path
        )
        let generated = context.generateProfile(extraAllowedPaths: [room.path]).generateScheme()
        XCTAssertTrue(generated.contains("deny file-write"))
        let profile = """
        (version 1)
        (deny default)
        (allow file-read*)
        (allow process-exec*)
        (allow process-fork)
        (allow signal)
        (allow sysctl-read)
        (allow file-write* (subpath "\(room.path)"))
        """
        let opened = try harness.client.send(
            commandRoom(.openSession(
                roomDir: room.path,
                envFile: room.envFile.path,
                shell: "zsh -r -f",
                seatbeltProfile: profile
            ))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        let exec = try harness.client.send(
            .exec(
                sessionID: sessionID,
                roomDir: room.path,
                argv: ["/usr/bin/touch", outside.path]
            )
        )
        let exitCode = exec.result?["exitCode"]?.int ?? 1
        XCTAssertNotEqual(exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    func testAttachStreamsOutputToTwoClients() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -r -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 3)
        let token = "T6ATTOK"
        let first = AttachCollector()
        let second = AttachCollector()
        let attachA = DispatchQueue(label: "t6.attach.a")
        let attachB = DispatchQueue(label: "t6.attach.b")
        var seededA = harness.client
        seededA.authority = SessionAuthorizer.commandRoomAuthority
        let clientA = seededA
        var seededB = harness.client
        seededB.authority = SessionAuthorizer.commandRoomAuthority
        let clientB = seededB
        attachA.async {
            do {
                try clientA.attach(sessionID: sessionID, onFrame: first.append)
            } catch {
                first.fail(error)
            }
        }
        attachB.async {
            do {
                try clientB.attach(sessionID: sessionID, onFrame: second.append)
            } catch {
                second.fail(error)
            }
        }
        XCTAssertTrue(first.waitForAttached(timeout: 5), first.errorText)
        XCTAssertTrue(second.waitForAttached(timeout: 5), second.errorText)
        var commander = harness.client
        commander.authority = SessionAuthorizer.commandRoomAuthority
        try commander.sendInput(
            sessionID: sessionID,
            bytes: Data("print \(token)\r".utf8)
        )
        XCTAssertTrue(first.waitForOutputFrame(timeout: 8), first.errorText)
        XCTAssertTrue(second.waitForOutputFrame(timeout: 8), second.errorText)
        _ = try harness.client.send(commandRoom(.closeSession(sessionID: sessionID)))
        XCTAssertTrue(first.waitForExit(timeout: 8), first.errorText)
        XCTAssertTrue(second.waitForExit(timeout: 8), second.errorText)
    }

    func testSessionOpsRejectForeignAllowChildAndCommandRoom() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let parent = try harness.makeRoom()
        let child = try harness.makeChild(of: parent)
        let foreign = try harness.makeRoom()
        let parentOpen = try harness.client.send(
            commandRoom(.openSession(roomDir: parent.path, envFile: parent.envFile.path, shell: "zsh -r"))
        )
        let childOpen = try harness.client.send(
            commandRoom(.openSession(roomDir: child.path, envFile: child.envFile.path, shell: "zsh -r"))
        )
        let foreignOpen = try harness.client.send(
            commandRoom(.openSession(roomDir: foreign.path, envFile: foreign.envFile.path, shell: "zsh -r"))
        )
        let parentID = try XCTUnwrap(parentOpen.result?["sessionID"]?.string)
        let childID = try XCTUnwrap(childOpen.result?["sessionID"]?.string)
        let foreignID = try XCTUnwrap(foreignOpen.result?["sessionID"]?.string)

        let closeForeign = try harness.client.send(
            DaemonRequest(op: .closeSession, sessionID: foreignID, roomSession: parentID)
        )
        XCTAssertEqual(closeForeign.error, SessionAuthorizer.foreignRoomError)

        let inputForeign = try harness.client.send(
            DaemonRequest(op: .input, sessionID: foreignID, input: "echo no\r", roomSession: parentID)
        )
        XCTAssertEqual(inputForeign.error, SessionAuthorizer.foreignRoomError)

        let attachForeign = try harness.client.send(
            DaemonRequest(op: .attach, sessionID: foreignID, roomSession: parentID)
        )
        XCTAssertEqual(attachForeign.error, SessionAuthorizer.foreignRoomError)

        let snapshotBare = try harness.client.send(
            DaemonRequest(op: .snapshot, sessionID: foreignID, lines: 10, roomSession: parentID)
        )
        XCTAssertEqual(snapshotBare.error, SessionAuthorizer.foreignRoomError)

        let childAttach = try harness.client.send(
            DaemonRequest(op: .attach, sessionID: childID, roomSession: parentID)
        )
        XCTAssertTrue(childAttach.ok, childAttach.error ?? "")
        XCTAssertEqual(childAttach.result?["attached"]?.bool, true)

        let childInput = try harness.client.send(
            DaemonRequest(op: .input, sessionID: childID, input: "true\r", roomSession: parentID)
        )
        XCTAssertTrue(childInput.ok, childInput.error ?? "")

        let commandClose = try harness.client.send(
            commandRoom(.closeSession(sessionID: foreignID))
        )
        XCTAssertTrue(commandClose.ok, commandClose.error ?? "")
    }

    func testBrokenFrameReportsErrorAndNextConnectionWorks() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let fd = try harness.client.connectOrSpawn()
        try UnixSocketIO.writeAll(fd: fd, data: Data([0, 0, 0, 0]))
        let payload = try UnixSocketIO.readFrame(fd: fd)
        let response = try DaemonFraming.decodeResponse(payload)
        Darwin.close(fd)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error, "zeroLengthFrame")
        let log = try String(contentsOf: harness.logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("zeroLengthFrame"), log)
        let listed = try harness.client.send(commandRoom(.listSessions()))
        XCTAssertTrue(listed.ok, listed.error ?? "")
    }

    func testAttachReplaySequence() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 3)

        let token1 = "REPLAY_TOKEN_123"
        var commander = harness.client
        commander.authority = SessionAuthorizer.commandRoomAuthority
        try commander.sendInput(sessionID: sessionID, bytes: Data("print \(token1)\r".utf8))
        XCTAssertTrue(harness.waitForSnapshot(sessionID: sessionID, containing: token1, timeout: 5))

        let collector = AttachCollector()
        let attachQueue = DispatchQueue(label: "test.attach.replay")
        var seededClient = harness.client
        seededClient.authority = SessionAuthorizer.commandRoomAuthority
        let client = seededClient
        attachQueue.async {
            do {
                try client.attach(sessionID: sessionID, lines: 100, replayBytes: 4096, onFrame: collector.append)
            } catch {
                collector.fail(error)
            }
        }

        XCTAssertTrue(collector.waitForAttached(timeout: 5), collector.errorText)
        XCTAssertTrue(collector.waitForReplayFrame(timeout: 5), collector.errorText)
        XCTAssertTrue(collector.waitForReplayEndFrame(timeout: 5), collector.errorText)

        let token2 = "LIVE_TOKEN_456"
        try commander.sendInput(sessionID: sessionID, bytes: Data("print \(token2)\r".utf8))
        XCTAssertTrue(collector.waitForOutputFrame(timeout: 8), collector.errorText)

        let frames = collector.frames
        let replayIdx = frames.firstIndex { $0.event == DaemonStreamEventName.replay }
        let replayEndIdx = frames.firstIndex { $0.event == DaemonStreamEventName.replayEnd }
        let liveIdx = frames.lastIndex { $0.event == DaemonStreamEventName.output }

        XCTAssertNotNil(replayIdx, "must contain replay frame")
        XCTAssertNotNil(replayEndIdx, "must contain replayEnd frame")
        XCTAssertNotNil(liveIdx, "must contain live output frame")

        if let r = replayIdx, let re = replayEndIdx, let l = liveIdx {
            XCTAssertLessThan(r, re, "replay must come before replayEnd")
            XCTAssertLessThan(re, l, "replayEnd must come before subsequent live output")
            let replayBytes = frames[r].outputBytes.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertTrue(replayBytes.contains(token1), "replay frame must contain token1: \(replayBytes)")
            let liveBytes = frames[l].outputBytes.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertTrue(liveBytes.contains(token2) || collector.outputText.contains(token2), "live frame must contain token2")
        }

        _ = try harness.client.send(commandRoom(.closeSession(sessionID: sessionID)))
        XCTAssertTrue(collector.waitForExit(timeout: 5), collector.errorText)
    }

    func testAttachRawClientStreamsReplayThenRealtime() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 3)

        let token1 = "RAW_REPLAY_AAA"
        var commander = harness.client
        commander.authority = SessionAuthorizer.commandRoomAuthority
        try commander.sendInput(sessionID: sessionID, bytes: Data("print \(token1)\r".utf8))
        XCTAssertTrue(harness.waitForSnapshot(sessionID: sessionID, containing: token1, timeout: 5))

        let rawCollector = RawAttachCollector()
        let attachQueue = DispatchQueue(label: "test.attach.raw")
        var seededClient = harness.client
        seededClient.authority = SessionAuthorizer.commandRoomAuthority
        let client = seededClient
        attachQueue.async {
            do {
                try client.attachRaw(
                    sessionID: sessionID,
                    replayBytes: 4096,
                    onBytes: rawCollector.appendBytes,
                    onReplayEnd: rawCollector.markReplayEnd
                )
            } catch {
                rawCollector.fail(error)
            }
        }

        XCTAssertTrue(rawCollector.waitForReplayEnd(timeout: 5), rawCollector.errorText)
        XCTAssertTrue(rawCollector.replayText.contains(token1), "replayed data must contain token1, got: \(rawCollector.replayText)")

        let token2 = "RAW_LIVE_BBB"
        try commander.sendInput(sessionID: sessionID, bytes: Data("print \(token2)\r".utf8))

        XCTAssertTrue(
            rawCollector.waitForLiveText(containing: token2, timeout: 5),
            "live output must be received after replayEnd, got: \(rawCollector.liveText)"
        )
        _ = try harness.client.send(commandRoom(.closeSession(sessionID: sessionID)))
    }

    func testResizeReflectedInWinsizeAndMultipleClients() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        guard let session = harness.server.sessionTable().get(sessionID) else {
            return XCTFail("session not found in sessionTable")
        }

        XCTAssertEqual(session.currentWindowSize.ws_col, 80)
        XCTAssertEqual(session.currentWindowSize.ws_row, 24)

        var clientA = harness.client
        clientA.authority = SessionAuthorizer.commandRoomAuthority
        try clientA.resize(sessionID: sessionID, columns: 120, rows: 40)

        XCTAssertEqual(session.currentWindowSize.ws_col, 120)
        XCTAssertEqual(session.currentWindowSize.ws_row, 40)
        XCTAssertEqual(session.terminalSize?.cols, 120)
        XCTAssertEqual(session.terminalSize?.rows, 40)

        if let fd = session.childFileDescriptor, fd >= 0 {
            var actual = winsize()
            let rc = Darwin.ioctl(fd, TIOCGWINSZ, &actual)
            XCTAssertEqual(rc, 0)
            XCTAssertEqual(actual.ws_col, 120)
            XCTAssertEqual(actual.ws_row, 40)
        }

        // Multiple subscribers: last request wins
        var clientB = harness.client
        clientB.authority = SessionAuthorizer.commandRoomAuthority
        try clientB.resize(sessionID: sessionID, columns: 100, rows: 30)

        XCTAssertEqual(session.currentWindowSize.ws_col, 100)
        XCTAssertEqual(session.currentWindowSize.ws_row, 30)
        XCTAssertEqual(session.terminalSize?.cols, 100)
        XCTAssertEqual(session.terminalSize?.rows, 30)

        if let fd = session.childFileDescriptor, fd >= 0 {
            var actual = winsize()
            let rc = Darwin.ioctl(fd, TIOCGWINSZ, &actual)
            XCTAssertEqual(rc, 0)
            XCTAssertEqual(actual.ws_col, 100)
            XCTAssertEqual(actual.ws_row, 30)
        }

        _ = try harness.client.send(commandRoom(.closeSession(sessionID: sessionID)))
    }

    func testRestrictedShellRawByteInputEnforcesPolicy() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -r -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 2)

        var commander = harness.client
        commander.authority = SessionAuthorizer.commandRoomAuthority
        try commander.sendInput(
            sessionID: sessionID,
            bytes: Data("/usr/local/bin/true\r".utf8)
        )
        let found = harness.waitForSnapshot(
            sessionID: sessionID,
            containing: "restricted",
            timeout: 5
        )
        let dump = harness.snapshotText(sessionID: sessionID)
        XCTAssertTrue(found, "expected restricted in snapshot, got: \(dump)")
    }

    func testOpenSessionWritesBannerInCRLFAndExposesInSnapshot() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let bannerText = "작업: 작업1\n완료 조건: 조건1\n쓰기 가능: path1\n도구: tool1\n종료하려면 exit 를 입력하세요"
        let opened = try harness.client.send(
            commandRoom(.openSession(
                roomDir: room.path,
                envFile: room.envFile.path,
                shell: "zsh -f",
                banner: bannerText
            ))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        let found = harness.waitForSnapshot(sessionID: sessionID, containing: "작업1", timeout: 3)
        XCTAssertTrue(found, "banner text should appear in snapshot")
        let snapshot = harness.snapshotText(sessionID: sessionID)
        XCTAssertTrue(snapshot.contains("완료 조건: 조건1"))
        XCTAssertTrue(snapshot.contains("종료하려면 exit 를 입력하세요"))
    }

    func testOpenSessionInitialDimensions() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(
                roomDir: room.path,
                envFile: room.envFile.path,
                shell: "zsh -f",
                columns: 120,
                rows: 40
            ))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        let session = harness.server.sessionTable().get(sessionID)
        XCTAssertEqual(session?.terminalSize?.cols, 120)
        XCTAssertEqual(session?.terminalSize?.rows, 40)
    }

    func testAttachStreamReceivesExitedFrameAndListSessionsReportsExitCode() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 3)

        let collector = AttachCollector()
        let attachQueue = DispatchQueue(label: "test.attach.exitcode")
        var seededClient = harness.client
        seededClient.authority = SessionAuthorizer.commandRoomAuthority
        let client = seededClient
        attachQueue.async {
            do {
                try client.attach(sessionID: sessionID, lines: 20, replayBytes: 1024, onFrame: collector.append)
            } catch {
                collector.fail(error)
            }
        }
        XCTAssertTrue(collector.waitForAttached(timeout: 5), collector.errorText)

        var commander = harness.client
        commander.authority = SessionAuthorizer.commandRoomAuthority
        try commander.sendInput(sessionID: sessionID, bytes: Data("exit 7\r".utf8))

        XCTAssertTrue(collector.waitForExit(timeout: 5), collector.errorText)
        let exitFrame = collector.frames.first { $0.event == DaemonStreamEventName.exited }
        XCTAssertNotNil(exitFrame)
        XCTAssertEqual(exitFrame?.code, 7)

        let listResp = try harness.client.send(commandRoom(.listSessions()))
        let sessions = listResp.result?["sessions"]?.array ?? []
        let match = sessions.first { $0["sessionID"]?.string == sessionID }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?["exitCode"]?.int, 7)
    }

    func testExecLaunchStreamsToLogAndPtySession() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 3)

        let exec = try harness.client.send(
            commandRoom(.exec(
                sessionID: sessionID, roomDir: room.path,
                argv: ["sh", "-c", "echo one; echo two"],
                launch: true))
        )
        XCTAssertTrue(exec.ok, exec.error ?? "")
        XCTAssertEqual(exec.result?["exitCode"]?.int, 0)

        let logURL = URL(fileURLWithPath: room.path).appendingPathComponent("launch.log")
        let logContent = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContent.contains("시작:"), "launch.log must have header")
        XCTAssertTrue(logContent.contains("one"), "launch.log must contain stdout")
        XCTAssertTrue(logContent.contains("two"), "launch.log must contain stdout")
        XCTAssertTrue(logContent.contains("종료 code=0"), "launch.log must have footer")

        let snapshot = harness.snapshotText(sessionID: sessionID)
        XCTAssertTrue(snapshot.contains("one"), "snapshot should contain 'one', got: \(snapshot)")
        XCTAssertTrue(snapshot.contains("two"), "snapshot should contain 'two', got: \(snapshot)")
    }

    func testExecLaunchWithoutSessionWritesLogOnly() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = try harness.client.send(commandRoom(.closeSession(sessionID: sessionID)))

        let exec = harness.server.handle(
            commandRoom(.exec(
                sessionID: nil, roomDir: room.path,
                argv: ["echo", "hello"],
                launch: true))
        )
        XCTAssertTrue(exec.ok, exec.error ?? "")
        XCTAssertEqual(exec.result?["exitCode"]?.int, 0)

        let logURL = URL(fileURLWithPath: room.path).appendingPathComponent("launch.log")
        let logContent = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContent.contains("hello"), "log must contain output")
        XCTAssertTrue(logContent.contains("시작:"), "log must have header")
        XCTAssertTrue(logContent.contains("종료 code=0"), "log must have footer")
    }

    func testExecLaunchTruncatesLargeOutput() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        let exec = try harness.client.send(
            commandRoom(.exec(
                sessionID: sessionID, roomDir: room.path,
                argv: ["awk", "BEGIN{for(i=0;i<20000;i++)print \"AAAA\"}"],
                launch: true))
        )
        XCTAssertTrue(exec.ok, exec.error ?? "")
        XCTAssertEqual(exec.result?["truncated"]?.bool, true)
        let stdout = exec.result?["stdout"]?.string ?? ""
        XCTAssertLessThanOrEqual(stdout.utf8.count, 64 * 1024)
    }

    func testLaunchLogTailReturnsLastLines() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)

        let exec = try harness.client.send(
            commandRoom(.exec(
                sessionID: sessionID, roomDir: room.path,
                argv: ["sh", "-c", "echo line1; echo line2; echo line3; echo line4"],
                launch: true))
        )
        XCTAssertTrue(exec.ok, exec.error ?? "")

        let logURL = URL(fileURLWithPath: room.path).appendingPathComponent("launch.log")
        let content = try String(contentsOf: logURL, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        let lastTwo = Array(lines.suffix(2))
        XCTAssertEqual(lastTwo.count, 2)
        XCTAssertTrue(lastTwo[1].contains("종료 code=0"))
    }

    func testSnapshotCacheReturnsCachedLinesWithoutReParsing() throws {
        let harness = try DaemonTestHarness.make(idleSeconds: 3600)
        defer { harness.stop() }
        let room = try harness.makeRoom()
        let opened = try harness.client.send(
            commandRoom(.openSession(roomDir: room.path, envFile: room.envFile.path, shell: "zsh -f"))
        )
        XCTAssertTrue(opened.ok, opened.error ?? "")
        let sessionID = try XCTUnwrap(opened.result?["sessionID"]?.string)
        _ = harness.waitForSnapshot(sessionID: sessionID, containing: "%", timeout: 3)

        let snap1 = harness.snapshotText(sessionID: sessionID)
        let snap2 = harness.snapshotText(sessionID: sessionID)
        XCTAssertEqual(snap1, snap2)
        XCTAssertFalse(snap1.isEmpty)
    }
}

private struct AttachState: Sendable {
    var frames: [DaemonStreamFrame] = []
    var errorText: String?
}

private final class AttachCollector: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: AttachState())

    func append(_ frame: DaemonStreamFrame) {
        state.withLock { $0.frames.append(frame) }
    }

    func fail(_ error: Error) {
        state.withLock { $0.errorText = String(describing: error) }
    }

    var errorText: String {
        state.withLock { bag in
            if let text = bag.errorText { return text }
            return bag.frames.map { String(describing: $0) }.joined(separator: "\n")
        }
    }

    var outputText: String {
        state.withLock { decodedOutput($0.frames) }
    }

    var outputByteCount: Int {
        state.withLock { decodedOutput($0.frames).utf8.count }
    }

    var frames: [DaemonStreamFrame] {
        state.withLock { $0.frames }
    }

    func waitForAttached(timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { frames in
            frames.contains { $0.result?["attached"]?.bool ?? false }
        }
    }

    func waitForReplayFrame(timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { frames in
            frames.contains { $0.event == DaemonStreamEventName.replay }
        }
    }

    func waitForReplayEndFrame(timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { frames in
            frames.contains { $0.event == DaemonStreamEventName.replayEnd }
        }
    }

    func waitForOutputFrame(timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { frames in
            frames.contains { $0.event == DaemonStreamEventName.output }
        }
    }

    func waitForMoreOutput(than baseline: Int, timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { frames in
            decodedOutput(frames).utf8.count > baseline
        }
    }

    func waitForExit(timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { frames in
            frames.contains { $0.event == DaemonStreamEventName.exit || $0.event == DaemonStreamEventName.exited }
        }
    }

    private func decodedOutput(_ frames: [DaemonStreamFrame]) -> String {
        frames.compactMap { frame -> String? in
            guard frame.event == DaemonStreamEventName.output else { return nil }
            guard let data = frame.outputBytes else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.joined()
    }

    private func wait(
        timeout: TimeInterval,
        predicate: ([DaemonStreamFrame]) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let copy = state.withLock { $0.frames }
            if predicate(copy) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}

private struct RawAttachState: Sendable {
    var replayEnded = false
    var replayData = Data()
    var liveData = Data()
    var errorText: String?
}

private final class RawAttachCollector: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: RawAttachState())

    func appendBytes(_ data: Data) {
        state.withLock {
            if $0.replayEnded {
                $0.liveData.append(data)
            } else {
                $0.replayData.append(data)
            }
        }
    }

    func markReplayEnd() {
        state.withLock { $0.replayEnded = true }
    }

    func fail(_ error: Error) {
        state.withLock { $0.errorText = String(describing: error) }
    }

    var errorText: String {
        state.withLock { $0.errorText ?? "" }
    }

    var replayEnded: Bool {
        state.withLock { $0.replayEnded }
    }

    var replayText: String {
        state.withLock { String(data: $0.replayData, encoding: .utf8) ?? "" }
    }

    var liveText: String {
        state.withLock { String(data: $0.liveData, encoding: .utf8) ?? "" }
    }

    func waitForReplayEnd(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if replayEnded { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    func waitForLiveText(containing needle: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if liveText.contains(needle) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}
