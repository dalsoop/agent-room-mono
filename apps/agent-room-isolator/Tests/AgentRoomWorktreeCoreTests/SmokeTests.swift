import AppScaffoldKit
import XCTest
import CommandKit
@testable import AgentRoomWorktreeCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-room-worktree"))
    }


}

final class RoomConceptTests: XCTestCase {
    func testRejectsEmptyTask() {
        XCTAssertThrowsError(try RoomConcept.validate(task: "  ", verify: "swift test")) { error in
            XCTAssertEqual(error as? AgentRoomWorktreeError, .taskEmpty)
        }
    }

    func testRejectsTrivialVerify() {
        XCTAssertThrowsError(try RoomConcept.validate(task: "fix lint", verify: "true")) { error in
            XCTAssertEqual(error as? AgentRoomWorktreeError, .trivialVerify("true"))
        }
    }

    func testSlugFromAsciiTask() {
        XCTAssertEqual(RoomConcept.slug(from: "Fix Room Worktree Bind", fallback: "x"), "fix-room-worktree-bind")
    }

    func testSlugFallsBackWhenNoAscii() {
        XCTAssertEqual(RoomConcept.slug(from: "방 개념", fallback: "room-ko"), "room-ko")
    }
}

final class OccupantIdentityTests: XCTestCase {
    func testReadsForgeActor() {
        XCTAssertEqual(
            OccupantIdentity.fromEnvironment(["FORGE_ACTOR": "agent:test@macbook"]),
            "agent:test@macbook"
        )
    }

    func testMissingIdentityIsNil() {
        XCTAssertNil(OccupantIdentity.fromEnvironment([:]))
    }
}

final class RoomBirthDocumentTests: XCTestCase {
    func testRendersPlaceholders() {
        let bind = RoomWorktreeBind(
            roomID: "RID",
            planID: "PID",
            slug: "demo-room",
            task: "lock room concept",
            verify: "swift test --filter RoomConceptTests",
            worktreePath: "/tmp/wt",
            branch: "demo-room",
            repoPath: "/tmp/repo",
            tenantID: "tenant:personal",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let room = RoomBirthDocuments.render(name: "ROOM.md", bind: bind, wallPreset: "toolbelt", network: false)
        XCTAssertTrue(room.contains("lock room concept"))
        XCTAssertTrue(room.contains("`RID`"))
        XCTAssertTrue(room.contains("/tmp/wt"))
        XCTAssertFalse(room.contains("{{TASK}}"))
        let agents = RoomBirthDocuments.render(name: "AGENTS.md", bind: bind, wallPreset: "toolbelt", network: false)
        XCTAssertTrue(agents.contains("swift test --filter RoomConceptTests"))
    }
}

final class ProvisionTests: XCTestCase {
    struct MockRunner: CommandRunning {
        let stdout: String
        func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
            CommandResult(stdout: stdout, stderr: "", exitCode: 0)
        }
    }

    func isolatedEnv() throws -> [String: String] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("arw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ["SWIFT_APP_STATE_ROOT": root.path]
    }

    func testDryRunDoesNotCallRunner() async throws {
        struct FailRunner: CommandRunning {
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                XCTFail("dry-run must not run sibling CLIs")
                return CommandResult(stdout: "", stderr: "no", exitCode: 1)
            }
        }
        let env = try isolatedEnv()
        let svc = AgentRoomWorktreeService(runner: FailRunner(), environment: env)
        let result = try await svc.provision(ProvisionRequest(
            task: "emit room md",
            verify: "swift test --filter RoomBirthDocumentTests",
            repoPath: "/tmp/swift-app-mono",
            name: "emit-room-md",
            occupant: "agent:test@macbook",
            quote: "emit room md",
            dryRun: true,
            spawn: true
        ))
        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.bind.slug, "emit-room-md")
        XCTAssertTrue(result.bind.worktreePath.hasSuffix(".worktrees/emit-room-md"))
    }

    func testProvisionWritesBindAndDocuments() async throws {
        let spawnJSON = """
        {"ok":true,"payload":{"roomID":"ROOM-1","planID":"PLAN-1"}}
        """
        let env = try isolatedEnv()
        let svc = AgentRoomWorktreeService(runner: MockRunner(stdout: spawnJSON), environment: env)
        let result = try await svc.provision(ProvisionRequest(
            task: "bind git worktree to room",
            verify: "swift test --filter ProvisionTests",
            repoPath: "/tmp/repo",
            name: "bind-git-wt",
            occupant: "agent:test@macbook",
            quote: "bind git worktree to room",
            dryRun: false,
            spawn: true
        ))
        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.bind.roomID, "ROOM-1")
        XCTAssertEqual(result.bind.planID, "PLAN-1")
        let listed = try await svc.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(result.documents.count, 3)
        for path in result.documents {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
        let shown = try await svc.show(roomID: "ROOM-1")
        XCTAssertEqual(shown.task, "bind git worktree to room")
        let snaps = try svc.documentSnapshots(roomID: "ROOM-1")
        XCTAssertEqual(snaps.count, 3)
        XCTAssertTrue(snaps.allSatisfy(\.exists))
        XCTAssertTrue(snaps.contains(where: { $0.name == "ROOM.md" && $0.preview.contains("bind git worktree to room") }))
        let roomBind = RoomWorktreePaths.roomDirectory(id: "ROOM-1", tenantID: result.bind.tenantID, environment: env)
            .appendingPathComponent("bind.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: roomBind.path))
    }

    func testSpawnJSONWithoutIDsFails() async throws {
        let env = try isolatedEnv()
        let svc = AgentRoomWorktreeService(
            runner: MockRunner(stdout: "{\"ok\":true,\"payload\":{}}"),
            environment: env
        )
        do {
            _ = try await svc.provision(ProvisionRequest(
                task: "must fail",
                verify: "swift test --filter RoomConceptTests",
                repoPath: "/tmp/repo",
                name: "must-fail",
                occupant: "agent:test@macbook",
                quote: "must fail",
                dryRun: false,
                spawn: true
            ))
            XCTFail("invented IDs are not allowed")
        } catch AgentRoomWorktreeError.spawnRoomFailed {
            // expected
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}

final class TraceTests: XCTestCase {
    struct DispatchRunner: CommandRunning {
        let worktreePath: String
        func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
            if arguments.contains("spawn-room") {
                return CommandResult(
                    stdout: "{\"ok\":true,\"payload\":{\"roomID\":\"ROOM-1\",\"planID\":\"PLAN-1\"}}\n",
                    stderr: "", exitCode: 0
                )
            }
            if arguments.contains("placement") {
                return CommandResult(
                    stdout: """
                    {"ok":true,"payload":{"id":"PLAN-1","state":"waiting",\
                    "rooms":[{"id":"ROOM-1","occupant":"agent:test@macbook"}]}}
                    """,
                    stderr: "", exitCode: 0
                )
            }
            if arguments.contains("--porcelain") {
                return CommandResult(
                    stdout: "worktree \(worktreePath)\nbranch refs/heads/bind-git-wt\n",
                    stderr: "", exitCode: 0
                )
            }
            return CommandResult(stdout: "ok\n", stderr: "", exitCode: 0)
        }
    }

    func testTraceLinksLedgerAndGit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("arw-trace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let env = ["SWIFT_APP_STATE_ROOT": root.path]
        let repo = root.appendingPathComponent("repo").path
        let wt = (repo as NSString).appendingPathComponent(".worktrees/bind-git-wt")
        try FileManager.default.createDirectory(atPath: wt, withIntermediateDirectories: true)
        let svc = AgentRoomWorktreeService(
            runner: DispatchRunner(worktreePath: (wt as NSString).standardizingPath),
            environment: env
        )
        _ = try await svc.provision(ProvisionRequest(
            task: "trace ledger and git",
            verify: "swift test --filter TraceTests",
            repoPath: repo,
            name: "bind-git-wt",
            occupant: "agent:test@macbook",
            quote: "trace ledger and git",
            dryRun: false,
            spawn: true
        ))
        let t = try await svc.trace(roomID: "ROOM-1")
        XCTAssertTrue(t.ledger.ok)
        XCTAssertEqual(t.ledger.state, "waiting")
        XCTAssertEqual(t.ledger.occupant, "agent:test@macbook")
        XCTAssertTrue(t.worktree.pathExists)
        XCTAssertTrue(t.worktree.listedByGit)
        XCTAssertTrue(t.worktree.markerOK)
        XCTAssertTrue(t.ok)
        let report = try await svc.doctor()
        XCTAssertTrue(report.ok, report.findings.joined(separator: ","))
    }

    func testPlacementListParseSkipsAbandoned() {
        let json = """
        {"ok":true,"payload":[
          {"id":"PLAN-1","state":"executing","tenantID":"tenant:personal","title":"t",
           "rooms":[{"id":"ROOM-1","blueprintSlug":"live","task":"live birth","state":"waiting"}]},
          {"id":"PLAN-X","state":"abandoned","tenantID":"tenant:personal","title":"old",
           "rooms":[{"id":"ROOM-X","blueprintSlug":"old","task":"old","state":"done"}]}
        ]}
        """
        let binds = PlacementListJSON.parse(json)
        XCTAssertEqual(binds.count, 1)
        XCTAssertEqual(binds[0].roomID, "ROOM-1")
        XCTAssertEqual(binds[0].planID, "PLAN-1")
        XCTAssertEqual(binds[0].task, "live birth")
    }

    func testPlacementParseReadsRoomIDField() {
        let json = """
        {"ok":true,"payload":{"planID":"PLAN-1","state":"executing","rooms":[{"roomID":"ROOM-1","state":"waiting"}]}}
        """
        let t = PlacementShowJSON.parse(stdout: json, expectedRoomID: "ROOM-1", planID: "PLAN-1")
        XCTAssertTrue(t.ok)
        XCTAssertEqual(t.state, "executing")
    }
}
