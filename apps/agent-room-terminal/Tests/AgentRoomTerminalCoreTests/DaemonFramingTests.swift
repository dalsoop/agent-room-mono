import XCTest
@testable import AgentRoomTerminalCore

final class DaemonFramingTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let request = DaemonRequest.openSession(
            roomDir: "/tmp/room",
            envFile: "/tmp/room/env",
            shell: "zsh -r",
            seatbeltProfile: "(version 1)"
        )
        let frame = try DaemonFraming.encode(request)
        XCTAssertGreaterThan(frame.count, 4)
        var decoder = DaemonFrameDecoder()
        let payloads = try decoder.append(frame)
        XCTAssertEqual(payloads.count, 1)
        let decoded = try DaemonFraming.decodeRequest(payloads[0])
        XCTAssertEqual(decoded, request)
    }

    func testResizeAndAttachReplayRequestRoundTrip() throws {
        let resize = DaemonRequest.resize(sessionID: "sess-1", columns: 120, rows: 40)
        let resizeFrame = try DaemonFraming.encode(resize)
        var decoder = DaemonFrameDecoder()
        let resizePayloads = try decoder.append(resizeFrame)
        XCTAssertEqual(try DaemonFraming.decodeRequest(resizePayloads[0]), resize)

        let attach = DaemonRequest.attach(sessionID: "sess-1", lines: 50, replayBytes: 1024)
        let attachFrame = try DaemonFraming.encode(attach)
        decoder = DaemonFrameDecoder()
        let attachPayloads = try decoder.append(attachFrame)
        XCTAssertEqual(try DaemonFraming.decodeRequest(attachPayloads[0]), attach)
    }

    func testResponseRoundTrip() throws {
        let response = DaemonResponse.success(
            .object(["sessionID": .string("abc"), "pgid": .int(9)]),
            generation: 4
        )
        let frame = try DaemonFraming.encode(response)
        var decoder = DaemonFrameDecoder()
        let payloads = try decoder.append(frame)
        let decoded = try DaemonFraming.decodeResponse(payloads[0])
        XCTAssertEqual(decoded, response)
        XCTAssertEqual(decoded.generation, 4)
        XCTAssertEqual(decoded.result?["sessionID"]?.string, "abc")
    }

    func testSplitHeaderThenPayload() throws {
        let request = DaemonRequest.listSessions()
        let frame = try DaemonFraming.encode(request)
        var decoder = DaemonFrameDecoder()
        let first = try decoder.append(frame.prefix(2))
        XCTAssertTrue(first.isEmpty)
        let rest = try decoder.append(frame.dropFirst(2))
        XCTAssertEqual(rest.count, 1)
        XCTAssertEqual(try DaemonFraming.decodeRequest(rest[0]), request)
    }

    func testZeroLengthFrameRejected() {
        var decoder = DaemonFrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0]))) { error in
            XCTAssertEqual(error as? DaemonFrameError, .zeroLengthFrame)
        }
    }

    func testAuthorizationAllowsChildOnly() {
        let parent = "/tmp/rooms/parent"
        let child = "/tmp/rooms/parent/children/child"
        let other = "/tmp/rooms/other"
        XCTAssertTrue(SessionAuthorization.allows(sessionRoomDir: parent, targetRoomDir: parent))
        XCTAssertTrue(SessionAuthorization.allows(sessionRoomDir: parent, targetRoomDir: child))
        XCTAssertFalse(SessionAuthorization.allows(sessionRoomDir: child, targetRoomDir: parent))
        XCTAssertFalse(SessionAuthorization.allows(sessionRoomDir: parent, targetRoomDir: other))
    }

    func testSessionAuthorizerCommandRoomAndForeign() {
        let parent = SessionPrincipal(sessionID: "sa", roomDir: "/tmp/rooms/parent")
        let child = SessionPrincipal(sessionID: "sc", roomDir: "/tmp/rooms/parent/children/child")
        let other = SessionPrincipal(sessionID: "sb", roomDir: "/tmp/rooms/other")
        XCTAssertTrue(SessionAuthorizer.allows(requester: parent, target: child))
        XCTAssertTrue(SessionAuthorizer.allows(requester: parent, target: parent))
        XCTAssertFalse(SessionAuthorizer.allows(requester: parent, target: other))
        XCTAssertFalse(SessionAuthorizer.allows(requester: child, target: parent))
        XCTAssertFalse(SessionAuthorizer.allows(requester: SessionPrincipal(), target: other))
        XCTAssertTrue(
            SessionAuthorizer.allows(requester: .commandRoom(), target: other)
        )
        XCTAssertEqual(SessionAuthorizer.foreignRoomError, "foreignRoom")
    }

    func testExecRequestWithRawAndToolRoundTrip() throws {
        let request = DaemonRequest.exec(
            sessionID: nil,
            roomDir: "/tmp/room",
            argv: ["echo", "hello"],
            raw: true,
            tool: "agy"
        )
        XCTAssertEqual(request.raw, true)
        XCTAssertEqual(request.tool, "agy")
        let frame = try DaemonFraming.encode(request)
        var decoder = DaemonFrameDecoder()
        let payloads = try decoder.append(frame)
        let decoded = try DaemonFraming.decodeRequest(payloads[0])
        XCTAssertEqual(decoded.raw, true)
        XCTAssertEqual(decoded.tool, "agy")
        XCTAssertEqual(decoded, request)
    }

    func testExecDefaultsToLaunchNotRaw() throws {
        let request = DaemonRequest.exec(
            sessionID: nil,
            roomDir: "/tmp/room",
            argv: ["ls"]
        )
        XCTAssertNil(request.raw)
        XCTAssertNil(request.launch)
    }

    func testGenerationStoreIncrements() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("gen")
        let store = GenerationStore(url: url)
        let first = try store.bump()
        let second = try store.bump()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
    }
}
