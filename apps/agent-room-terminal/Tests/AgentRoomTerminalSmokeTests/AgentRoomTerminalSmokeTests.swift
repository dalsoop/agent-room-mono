import Foundation
import XCTest
import CommandKit
import RoomKit
@testable import AgentRoomTerminalCore

final class AgentRoomTerminalSmokeTests: XCTestCase {
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

    func testOpenExecCloseDoesNotDeadlockOnLargeLedgerJSON() throws {
        guard Self.canApplySandboxExec() else {
            throw XCTSkip("sandbox-exec not permitted in current environment")
        }
        let harness = try SmokeHarness.make()
        addTeardownBlock { harness.tearDown() }

        let started = harness.run(["daemon", "start", "--json"])
        XCTAssertEqual(started.exitCode, 0, started.stderr + started.stdout)

        let opened = harness.run([
            "open", Self.roomID, "--execute", "--json",
        ], timeout: 60)
        XCTAssertEqual(opened.exitCode, 0, opened.stderr + opened.stdout)

        let listed = harness.run(["exec", Self.roomID, "--json", "--", "ls", "bin"])
        XCTAssertEqual(listed.exitCode, 0, listed.stderr + listed.stdout)

        let blocked = harness.run(["exec", Self.roomID, "--json", "--", "/usr/bin/true"])
        let blockedText = blocked.stderr + blocked.stdout
        XCTAssertNotEqual(blocked.exitCode, 0, blockedText)
        XCTAssertTrue(
            blockedText.contains("restricted")
                || blockedText.contains("path execution")
                || blockedText.contains("\"ok\":false")
                || blockedText.contains("DaemonProtocolError"),
            blockedText
        )

        let closed = harness.run(["close", Self.roomID, "--execute", "--json"])
        XCTAssertEqual(closed.exitCode, 0, closed.stderr + closed.stdout)

        let stopped = harness.run(["daemon", "stop", "--json"])
        XCTAssertEqual(stopped.exitCode, 0, stopped.stderr + stopped.stdout)
    }

    func testHandoffPersistsPitfallsAndSimulateCallsHandover() throws {
        let harness = try SmokeHarness.make()
        addTeardownBlock { harness.tearDown() }

        XCTAssertEqual(harness.run(["daemon", "start", "--json"]).exitCode, 0)
        let opened = harness.run(["open", Self.roomID, "--execute", "--json"], timeout: 60)
        XCTAssertEqual(opened.exitCode, 0, opened.stderr + opened.stdout)
        let roomPath = try XCTUnwrap(harness.jsonString(opened.stdout, key: "path"))

        try harness.writeUsageOverHandoff(roomPath: roomPath)
        let budget = harness.run(["budget", Self.roomID, "--json"])
        XCTAssertEqual(budget.exitCode, 0, budget.stderr + budget.stdout)
        XCTAssertEqual(harness.jsonString(budget.stdout, key: "state"), "handoff-due")

        let handed = harness.run([
            "handoff", Self.roomID, "--execute", "--note", "x", "--pitfall", "p",
        ], timeout: 60)
        XCTAssertEqual(handed.exitCode, 0, handed.stderr + handed.stdout)
        let bottleID = try XCTUnwrap(harness.jsonString(handed.stdout, key: "id"))
        let bottleURL = URL(fileURLWithPath: roomPath)
            .appendingPathComponent("handoff", isDirectory: true)
            .appendingPathComponent("\(bottleID).json")
        let bottle = try JSONDecoder().decode(AgentRoomTerminalCore.HandoffDigest.self, from: try Data(contentsOf: bottleURL))
        XCTAssertEqual(bottle.pitfalls, ["p"])
        let eventLog = RoomEventLog(roomURL: URL(fileURLWithPath: roomPath))
        let events = eventLog.read().events
        XCTAssertTrue(events.contains { $0.kind == RoomEventKind.handoffNoted })

        let simulated = harness.run([
            "simulate", Self.roomID, "--execute", "--against", bottleID, "--json",
        ], timeout: 60)
        XCTAssertEqual(simulated.exitCode, 0, simulated.stderr + simulated.stdout)
        _ = harness.run(["close", Self.roomID, "--execute", "--json"])
        _ = harness.run(["daemon", "stop", "--json"])
    }
}
