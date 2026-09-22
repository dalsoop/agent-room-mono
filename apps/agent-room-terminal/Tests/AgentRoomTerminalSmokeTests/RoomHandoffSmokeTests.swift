import Foundation
import XCTest
import CommandKit
import RoomKit
@testable import AgentRoomTerminalCore

final class RoomHandoffSmokeTests: XCTestCase {
    static let roomID = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    static let planID = "550e8400-e29b-41d4-a716-446655440000"

    private static func canApplySandboxExec() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)", "/usr/bin/true"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    override func tearDown() {
        DaemonProcessReaper.reapAllTestDaemons()
        super.tearDown()
    }

    func testHandoffLifecycleWithForcedBudgetExhaustionAndSimulation() throws {
        guard Self.canApplySandboxExec() else {
            throw XCTSkip("sandbox-exec not permitted in current environment")
        }
        let harness = try SmokeHarness.make(roomID: Self.roomID, planID: Self.planID)
        addTeardownBlock { harness.tearDown() }

        // 1. Start daemon
        let started = harness.run(["daemon", "start", "--json"])
        XCTAssertEqual(started.exitCode, 0, started.stderr + started.stdout)

        // 2. Open room
        let opened = harness.run(["open", Self.roomID, "--execute", "--json"], timeout: 60)
        XCTAssertEqual(opened.exitCode, 0, opened.stderr + opened.stdout)
        guard let roomPath = harness.jsonString(opened.stdout, key: "path") else {
            XCTFail("expected path in open response: \(opened.stdout)")
            return
        }

        // 3. Force budget exhaustion
        try harness.writeUsageOverHandoff(roomPath: roomPath)

        // 4. Budget check verifies handoff is due
        let budget = harness.run(["budget", Self.roomID, "--json"])
        XCTAssertEqual(budget.exitCode, 0, budget.stderr + budget.stdout)
        XCTAssertEqual(harness.jsonString(budget.stdout, key: "state"), "handoff-due")

        // 5. Execute handoff note & bottle creation
        let handoff = harness.run([
            "handoff", Self.roomID,
            "--note", "handoff smoke test",
            "--pitfall", "smoke pitfall",
            "--summary", "smoke summary",
            "--instruction", "continue smoke execution",
            "--execute",
            "--json",
        ])
        XCTAssertEqual(handoff.exitCode, 0, handoff.stderr + handoff.stdout)
        guard let bottleID = harness.jsonString(handoff.stdout, key: "id") else {
            XCTFail("expected bottle id in handoff response: \(handoff.stdout)")
            return
        }

        // Verify spec updated with bottleSwapCount and simulating handoverState
        let specURL = URL(fileURLWithPath: roomPath).appendingPathComponent("spec.json")
        let specData = try Data(contentsOf: specURL)
        let specJSON = try JSONSerialization.jsonObject(with: specData) as? [String: Any]
        XCTAssertEqual(specJSON?["bottleSwapCount"] as? Int, 1)
        XCTAssertEqual(specJSON?["handoverState"] as? String, "simulating")

        // Verify event log contains bottleSwapped and handoffNoted
        let eventLog = RoomEventLog(roomURL: URL(fileURLWithPath: roomPath))
        let events = eventLog.read().events
        XCTAssertTrue(events.contains(where: { $0.kind == RoomEventKind.bottleSwapped }))
        XCTAssertTrue(events.contains(where: { $0.kind == RoomEventKind.handoffNoted }))

        // 6. Execute simulation against bottle -> successor passes, predecessor vacated
        let simulated = harness.run([
            "simulate", Self.roomID,
            "--against", bottleID,
            "--execute",
            "--json",
        ], timeout: 60)
        XCTAssertEqual(simulated.exitCode, 0, simulated.stderr + simulated.stdout)

        // Verify spec updated to handoverState "passed"
        let postSpecData = try Data(contentsOf: specURL)
        let postSpecJSON = try JSONSerialization.jsonObject(with: postSpecData) as? [String: Any]
        XCTAssertEqual(postSpecJSON?["handoverState"] as? String, "passed")

        // Verify events contain vacated and occupied (successor seated)
        let postEvents = eventLog.read().events
        XCTAssertTrue(postEvents.contains(where: { $0.kind == RoomEventKind.vacated }))
        XCTAssertTrue(postEvents.contains(where: { $0.kind == RoomEventKind.occupied }))

        // 7. Close room and stop daemon
        let closed = harness.run(["close", Self.roomID, "--execute", "--json"])
        XCTAssertEqual(closed.exitCode, 0, closed.stderr + closed.stdout)
        let stopped = harness.run(["daemon", "stop", "--json"])
        XCTAssertEqual(stopped.exitCode, 0, stopped.stderr + stopped.stdout)
    }

    func testSmokeHandoffCLICommandExecution() throws {
        guard Self.canApplySandboxExec() else {
            throw XCTSkip("sandbox-exec not permitted in current environment")
        }
        let harness = try SmokeHarness.make(roomID: Self.roomID, planID: Self.planID)
        addTeardownBlock { harness.tearDown() }

        // Start daemon
        let started = harness.run(["daemon", "start", "--json"])
        XCTAssertEqual(started.exitCode, 0, started.stderr + started.stdout)

        // Open room
        let opened = harness.run(["open", Self.roomID, "--execute", "--json"], timeout: 60)
        XCTAssertEqual(opened.exitCode, 0, opened.stderr + opened.stdout)

        // Run automated `smoke handoff <room-id> --execute --json`
        let smokeResult = harness.run([
            "smoke", "handoff", Self.roomID,
            "--execute",
            "--json",
        ], timeout: 90)
        XCTAssertEqual(smokeResult.exitCode, 0, smokeResult.stderr + smokeResult.stdout)

        guard let data = smokeResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("expected JSON output from smoke handoff: \(smokeResult.stdout)")
            return
        }

        let result = json["result"] as? [String: Any] ?? json
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual((result["roomID"] as? String)?.lowercased(), Self.roomID.lowercased())
        XCTAssertEqual(result["bottleSwapCount"] as? Int, 1)
        XCTAssertEqual(result["handoverState"] as? String, "passed")
        XCTAssertEqual(result["predecessorStatus"] as? String, "vacated")
        XCTAssertNotNil(result["bottleID"])

        // Close room and stop daemon
        _ = harness.run(["close", Self.roomID, "--execute", "--json"])
        _ = harness.run(["daemon", "stop", "--json"])
    }

    func testSmokeHandoffDryRunPlan() throws {
        guard Self.canApplySandboxExec() else {
            throw XCTSkip("sandbox-exec not permitted in current environment")
        }
        let harness = try SmokeHarness.make(roomID: Self.roomID, planID: Self.planID)
        addTeardownBlock { harness.tearDown() }

        // Run `smoke handoff <room-id> --json` without --execute
        let dryRun = harness.run([
            "smoke", "handoff", Self.roomID,
            "--json",
        ])
        XCTAssertEqual(dryRun.exitCode, 0, dryRun.stderr + dryRun.stdout)

        guard let data = dryRun.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("expected JSON output from dry-run: \(dryRun.stdout)")
            return
        }

        let result = json["result"] as? [String: Any] ?? json
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(result["dryRun"] as? Bool, true)
        XCTAssertEqual((result["roomID"] as? String)?.lowercased(), Self.roomID.lowercased())
        guard let steps = result["steps"] as? [String] else {
            XCTFail("expected steps array in dry run output: \(dryRun.stdout)")
            return
        }
        XCTAssertFalse(steps.isEmpty)
    }
}
