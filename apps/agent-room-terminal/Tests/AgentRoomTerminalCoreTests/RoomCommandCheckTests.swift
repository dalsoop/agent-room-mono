import XCTest
@testable import AgentRoomTerminalCore

final class RoomCommandCheckTests: XCTestCase {
    let roomEnv = [RoomCommandCheck.roomIDKey: "room-fixture"]
    let emptyEnv: [String: String] = [:]

    func testPassWithoutRoomIDEvenWhenAbsolute() {
        XCTAssertEqual(
            RoomCommandCheck.evaluate(command: "/usr/bin/ls", tool: nil, environment: emptyEnv),
            .allow
        )
    }

    func testPassWithoutRoomIDForAgentTool() {
        XCTAssertEqual(
            RoomCommandCheck.evaluate(command: "ls", tool: "Agent", environment: emptyEnv),
            .allow
        )
    }

    func testPassLsInRoom() {
        XCTAssertEqual(
            RoomCommandCheck.evaluate(command: "ls", tool: nil, environment: roomEnv),
            .allow
        )
    }

    func testPassGitStatusInRoom() {
        XCTAssertEqual(
            RoomCommandCheck.evaluate(command: "git status", tool: nil, environment: roomEnv),
            .allow
        )
    }

    func testPassCatInRoom() {
        XCTAssertEqual(
            RoomCommandCheck.evaluate(command: "cat ROOM.md", tool: nil, environment: roomEnv),
            .allow
        )
    }

    func testPassGrepInRoom() {
        XCTAssertEqual(
            RoomCommandCheck.evaluate(command: "grep foo", tool: nil, environment: roomEnv),
            .allow
        )
    }

    func testBlockAbsolutePath() {
        if case .deny = RoomCommandCheck.evaluate(
            command: "/usr/bin/true",
            tool: nil,
            environment: roomEnv
        ) {
            return
        }
        XCTFail("expected deny")
    }

    func testBlockAbsoluteAfterConnector() {
        if case .deny = RoomCommandCheck.evaluate(
            command: "ls; /bin/cat",
            tool: nil,
            environment: roomEnv
        ) {
            return
        }
        XCTFail("expected deny")
    }

    func testBlockEnvPath() {
        if case .deny = RoomCommandCheck.evaluate(
            command: "env PATH=/usr/bin ls",
            tool: nil,
            environment: roomEnv
        ) {
            return
        }
        XCTFail("expected deny")
    }

    func testBlockShDashC() {
        if case .deny = RoomCommandCheck.evaluate(
            command: "sh -c ls",
            tool: nil,
            environment: roomEnv
        ) {
            return
        }
        XCTFail("expected deny")
    }

    func testBlockPython3() {
        if case .deny = RoomCommandCheck.evaluate(
            command: "python3 -c print(1)",
            tool: nil,
            environment: roomEnv
        ) {
            return
        }
        XCTFail("expected deny")
    }

    func testBlockAgentToolInRoom() {
        if case .deny(let reason) = RoomCommandCheck.evaluate(
            command: "anything",
            tool: "Agent",
            environment: roomEnv
        ) {
            XCTAssertTrue(reason.contains("open"))
            return
        }
        XCTFail("expected deny")
    }
}
