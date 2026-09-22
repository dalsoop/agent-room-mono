import Foundation
import XCTest
@testable import AgentRoomTerminalCore

struct MockRemoteRoomRunner: RemoteRoomRunning, Sendable {
    var defaultResponse = RemoteRoomExecutionResult(exitCode: 0, stdout: "", stderr: "")

    func runRemote(
        host: String,
        remoteCommandLine: String,
        timeout: TimeInterval?
    ) async throws -> RemoteRoomExecutionResult {
        defaultResponse
    }

    func runRemoteSync(
        host: String,
        remoteCommandLine: String,
        timeout: TimeInterval?
    ) throws -> RemoteRoomExecutionResult {
        defaultResponse
    }
}

final class RoomOpsTests: XCTestCase {
    var tempHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-ops-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome, FileManager.default.fileExists(atPath: tempHome.path) {
            try FileManager.default.removeItem(at: tempHome)
        }
        try super.tearDownWithError()
    }

    func testEnterUsesProvidedHomeNotUserTenants() throws {
        let ctx = try RoomOps.enter(
            tenant: "tenant:acme",
            roomName: "room-acme-1",
            homeDirectory: tempHome.path
        )
        XCTAssertEqual(ctx.roomID, "room-acme-1")
        XCTAssertEqual(ctx.tenantSlug, "acme")
        XCTAssertTrue(ctx.sandboxDirectory.path.hasPrefix(tempHome.path))
        XCTAssertFalse(ctx.sandboxDirectory.path.contains(NSHomeDirectory() + "/.tenants"))
        try ctx.teardown(archive: false)
    }

    func testListRoomsEmptyWhenMissing() throws {
        let listed = try RoomOps.listRooms(
            environment: ["SWIFT_APP_STATE_ROOT": tempHome.path],
            homeDirectory: tempHome.path
        )
        XCTAssertEqual(listed, [])
    }

    func testRemoteCommandBuilderQuotesAndHost() {
        let quoted = RemoteRoomCommandBuilder.shellQuote("a b")
        XCTAssertEqual(quoted, "'a b'")
        let parsed = RemoteRoomCommandBuilder.parseHost(from: ["list", "--host", "box:22"])
        XCTAssertEqual(parsed.host, "box:22")
        XCTAssertEqual(parsed.remainingArgs, ["list"])
        let line = RemoteRoomCommandBuilder.buildRemoteCommandLine(args: ["status"])
        XCTAssertTrue(line.hasPrefix("agent-room-terminal room"))
    }

    func testMockRemoteRunnerRecords() throws {
        let mock = MockRemoteRoomRunner()
        let result = try RoomOps.routeRemote(
            host: "box",
            remoteCommandLine: "true",
            runner: mock
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.isSuccess)
    }
}
