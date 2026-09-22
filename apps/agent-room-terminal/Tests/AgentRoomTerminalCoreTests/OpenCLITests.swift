import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class OpenCLITests: XCTestCase {
    override func tearDown() {
        DaemonProcessReaper.reapAllTestDaemons()
        super.tearDown()
    }

    func testOpenSessionRequestIncludesSeatbeltProfile() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("seatbelt")
        defer { try? FileManager.default.removeItem(at: root) }
        try CLITestSupport.writeFixtureCLIs(root: root)
        let daemon = try CLITestSupport.startFakeDaemon(root: root)
        defer { daemon.terminate() }
        let env = CLITestSupport.openEnv(root: root)
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--execute", "--json"],
            extraEnv: env
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["seatbelt"] as? Bool, true)
        XCTAssertEqual(payload["reused"] as? Bool, false)
        let network = try XCTUnwrap(payload["network"] as? [String: Any])
        XCTAssertEqual(network["mode"] as? String, "open")
        XCTAssertEqual(network["allowedDomains"] as? [String], [])
        let requests = try CLITestSupport.requestLog(root: root)
        let openReq = try XCTUnwrap(requests.first { $0["op"] as? String == "openSession" })
        let profile = try XCTUnwrap(openReq["seatbeltProfile"] as? String)
        XCTAssertTrue(profile.contains("(version 1)"), profile)
        XCTAssertTrue(profile.contains("file-write"), profile)
        let encoded = try JSONEncoder().encode(
            DaemonRequest.openSession(
                roomDir: CLITestSupport.roomPath(root: root),
                envFile: CLITestSupport.roomPath(root: root) + "/env",
                shell: "zsh -r",
                seatbeltProfile: profile
            )
        )
        let decoded = try JSONDecoder().decode(DaemonRequest.self, from: encoded)
        XCTAssertEqual(decoded.seatbeltProfile, profile)
    }

    /// open 프리셋도 seatbelt 를 켠다(business-rules 벽 프리셋 표: 파일 쓰기만 제한, 네트워크 허용).
    func testOpenPresetKeepsSeatbeltWithNetwork() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("open-preset")
        defer { try? FileManager.default.removeItem(at: root) }
        try CLITestSupport.writeFixtureCLIs(
            root: root,
            fixture: .init(wallPreset: "open")
        )
        let daemon = try CLITestSupport.startFakeDaemon(root: root)
        defer { daemon.terminate() }
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--preset", "open", "--execute", "--json"],
            extraEnv: CLITestSupport.openEnv(root: root)
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["seatbelt"] as? Bool, true)
        let requests = try CLITestSupport.requestLog(root: root)
        let openReq = try XCTUnwrap(requests.first { $0["op"] as? String == "openSession" })
        let profile = try XCTUnwrap(openReq["seatbeltProfile"] as? String)
        XCTAssertFalse(profile.contains("(deny network*)"), "open 프리셋은 네트워크를 막지 않는다")
    }

    func testIdempotentReopenReusesLiveSession() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("reuse")
        defer { try? FileManager.default.removeItem(at: root) }
        let liveID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let roomPath = CLITestSupport.roomPath(root: root)
        try CLITestSupport.writeFixtureCLIs(
            root: root,
            fixture: .init(occupant: "agent:claude@host", occupantSession: liveID)
        )
        let daemon = try CLITestSupport.startFakeDaemon(
            root: root,
            preloadID: liveID,
            preloadRoom: roomPath
        )
        defer { daemon.terminate() }
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--execute", "--json"],
            extraEnv: CLITestSupport.openEnv(root: root)
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["reused"] as? Bool, true)
        XCTAssertEqual(payload["sessionID"] as? String, liveID)
        let ops = try CLITestSupport.requestLog(root: root).compactMap { $0["op"] as? String }
        XCTAssertFalse(ops.contains("openSession"))
        XCTAssertFalse(ops.contains("closeSession"))
        XCTAssertTrue(ops.contains("listSessions"))
    }

    func testSuccessorOpenCreatesNewSession() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("successor")
        defer { try? FileManager.default.removeItem(at: root) }
        let liveID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let roomPath = CLITestSupport.roomPath(root: root)
        try CLITestSupport.writeFixtureCLIs(
            root: root,
            fixture: .init(
                occupant: "agent:claude@host",
                occupantSession: liveID,
                handoverState: "simulating"
            )
        )
        let daemon = try CLITestSupport.startFakeDaemon(
            root: root,
            preloadID: liveID,
            preloadRoom: roomPath
        )
        defer { daemon.terminate() }
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--successor", "--tool", "grok", "--execute", "--json"],
            extraEnv: CLITestSupport.openEnv(root: root)
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["reused"] as? Bool, false)
        XCTAssertEqual(payload["sessionRole"] as? String, "successor")
        XCTAssertEqual(payload["predecessorSession"] as? String, liveID)
        let sessionID = try XCTUnwrap(payload["sessionID"] as? String)
        XCTAssertNotEqual(sessionID, liveID)
        let requests = try CLITestSupport.requestLog(root: root)
        XCTAssertTrue(requests.contains { $0["op"] as? String == "openSession" })
        let openReq = try XCTUnwrap(requests.first { $0["op"] as? String == "openSession" })
        XCTAssertEqual(openReq["sessionRole"] as? String, "successor")
        XCTAssertFalse(requests.contains { $0["op"] as? String == "closeSession" })
    }

    func testSuccessorOpenJoinsSimulatingLedgerWithoutHandover() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("succ-join")
        defer { try? FileManager.default.removeItem(at: root) }
        let liveID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let roomPath = CLITestSupport.roomPath(root: root)
        let handle = RoomOpenPolicy.successorHandle(sessionID: liveID)
        try CLITestSupport.writeFixtureCLIs(
            root: root,
            fixture: .init(
                occupant: "agent:claude@host",
                occupantSession: liveID,
                successorOccupant: "agent:grok@host",
                successorSession: handle,
                handoverState: "simulating"
            )
        )
        let daemon = try CLITestSupport.startFakeDaemon(
            root: root,
            preloadID: liveID,
            preloadRoom: roomPath
        )
        defer { daemon.terminate() }
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--successor", "--tool", "grok", "--execute", "--json"],
            extraEnv: CLITestSupport.openEnv(root: root)
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["sessionRole"] as? String, "successor")
        XCTAssertEqual(payload["ledger"] as? String, "joined-existing-handover")
        let log = try CLITestSupport.ledgerLog(root: root)
        XCTAssertFalse(log.contains { $0.contains("handover") }, log.joined(separator: "\n"))
        XCTAssertFalse(log.contains { $0.contains("--successor") }, log.joined(separator: "\n"))
        XCTAssertFalse(log.contains { $0.contains("occupy") }, log.joined(separator: "\n"))
    }

    func testSuccessorOpenCallsHandoverWhenNotSimulating() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("succ-handover")
        defer { try? FileManager.default.removeItem(at: root) }
        let liveID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let roomPath = CLITestSupport.roomPath(root: root)
        try CLITestSupport.writeFixtureCLIs(
            root: root,
            fixture: .init(
                occupant: "agent:claude@host",
                occupantSession: liveID,
                handoverState: "none"
            )
        )
        let daemon = try CLITestSupport.startFakeDaemon(
            root: root,
            preloadID: liveID,
            preloadRoom: roomPath
        )
        defer { daemon.terminate() }
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--successor", "--tool", "grok", "--execute", "--json"],
            extraEnv: CLITestSupport.openEnv(root: root)
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["sessionRole"] as? String, "successor")
        XCTAssertNil(payload["ledger"] as? String)
        let eventLog = RoomEventLog(roomURL: URL(fileURLWithPath: roomPath))
        let events = eventLog.read().events
        XCTAssertTrue(events.contains { $0.kind == RoomEventKind.occupied })
    }

    func testOccupyFailureClosesOpenedSession() throws {
        XCTAssertFalse(CLITestSupport.roomID.isEmpty)
        throw XCTSkip("Replaced by local RoomEventLog append without ledger reverse calls")
    }

    func testVerdictRunnableThreeCases() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let cases: [(
            fixture: CLITestSupport.LedgerFixture,
            runnable: Bool,
            reasonContains: String?
        )] = [
            (.init(toolbelt: ["ls"], verdict: "ls"), true, nil),
            (
                .init(toolbelt: ["ls"], verdict: "kubectl"),
                false,
                "not in toolbelt"
            ),
            (
                .init(toolbelt: ["bad-cli"], verdict: "bad-cli"),
                false,
                "excluded"
            ),
        ]
        for item in cases {
            try assertVerdict(cli: cli, item: item)
        }
    }

    private func assertVerdict(
        cli: URL,
        item: (
            fixture: CLITestSupport.LedgerFixture,
            runnable: Bool,
            reasonContains: String?
        )
    ) throws {
        let root = try makeRoot("verdict")
        defer { try? FileManager.default.removeItem(at: root) }
        try CLITestSupport.writeFixtureCLIs(root: root, fixture: item.fixture)
        let daemon = try CLITestSupport.startFakeDaemon(root: root)
        defer { daemon.terminate() }
        let opened = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--execute", "--json"],
            extraEnv: CLITestSupport.openEnv(root: root)
        )
        XCTAssertEqual(opened.exit, 0, opened.stderr + opened.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(opened.stdout))
        XCTAssertEqual(payload["verdictRunnable"] as? Bool, item.runnable, item.fixture.verdict)
        if let needle = item.reasonContains {
            let reason = payload["verdictReason"] as? String ?? ""
            XCTAssertTrue(reason.contains(needle), reason)
            XCTAssertTrue(opened.stderr.contains("verdict not runnable"), opened.stderr)
        } else {
            XCTAssertNil(payload["verdictReason"])
        }
    }

    func testOpenWithSpecFileLoadsRoomSpecDirectly() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("open-spec")
        defer { try? FileManager.default.removeItem(at: root) }
        let specFile = root.appendingPathComponent("spec.json")
        let roomSpec = RoomSpec(
            roomID: UUID(),
            tenant: "tenant:alpha",
            task: "Solve issue with spec",
            verdict: "true",
            walls: RoomWalls(shell: .restricted),
            launch: RoomLaunch(tool: .claude, promptText: "Fix bug")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(roomSpec)
        try data.write(to: specFile)

        let env = CLITestSupport.openEnv(root: root)
        let dryRun = CLITestSupport.runCLI(
            cli,
            ["open", "--spec", specFile.path, "--json"],
            extraEnv: env
        )
        XCTAssertEqual(dryRun.exit, 0, dryRun.stderr + dryRun.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(dryRun.stdout))
        XCTAssertEqual(payload["command"] as? String, "open")
        XCTAssertEqual(payload["spec"] as? String, specFile.path)
        let steps = try XCTUnwrap(payload["steps"] as? [String])
        XCTAssertEqual(steps.first, "spec-load")
    }

    func testOpenDryRunIncludesNote() throws {
        let cli = try XCTUnwrap(CLITestSupport.product("agent-room-terminal"))
        let root = try makeRoot("dryrun-note")
        defer { try? FileManager.default.removeItem(at: root) }
        try CLITestSupport.writeFixtureCLIs(root: root)
        let env = CLITestSupport.openEnv(root: root)
        let dryRun = CLITestSupport.runCLI(
            cli,
            ["open", CLITestSupport.roomID, "--json"],
            extraEnv: env
        )
        XCTAssertEqual(dryRun.exit, 0, dryRun.stderr + dryRun.stdout)
        let payload = try XCTUnwrap(CLITestSupport.payload(dryRun.stdout))
        XCTAssertEqual(payload["dryRun"] as? Bool, true)
        XCTAssertEqual(payload["note"] as? String, "dry-run — 실제로 열려면 --execute")
    }

    private func makeRoot(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent(
                "art-\(label)-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
