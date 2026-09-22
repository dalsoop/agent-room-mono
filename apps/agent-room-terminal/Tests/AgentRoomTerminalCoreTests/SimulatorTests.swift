import XCTest
@testable import AgentRoomTerminalCore

final class SimulatorTests: XCTestCase {
    var room: URL!

    override func tearDownWithError() throws {
        if let room {
            try FileManager.default.removeItem(at: room)
        }
        try super.tearDownWithError()
    }

    func testNoCandidatesPassesHonestly() async throws {
        room = try HabitRoomFixture.makeRoom(
            snapshot: "healthy\n",
            termLog: "healthy\n"
        )
        let log = OrderLog()
        let exec = SpyExec(log: log)
        let ledger = SpyLedger(log: log)
        let verdict = try await makeSimulator(
            store: HabitStore(),
            exec: exec,
            ledger: ledger
        ).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(verdict.passed)
        XCTAssertEqual(verdict.reason, "no-habits")
        XCTAssertEqual(verdict.steps, [])
        XCTAssertEqual(exec.closes, [HabitTestIDs.session])
        XCTAssertEqual(ledger.states, ["passed"])
    }

    func testCandidateReplaySplitsExecutedAndCompared() async throws {
        let logText = """
        kubectl get pods
        NAME ready
        healthy
        """
        room = try HabitRoomFixture.makeRoom(
            snapshot: logText,
            termLog: logText,
            candidates: [
                HabitCandidate(
                    ts: "2026-09-04T00:00:00Z",
                    argv: ["safe-cli", "status"],
                    exitCode: 0,
                    durationMs: 8,
                    tool: "claude"
                ),
                HabitCandidate(
                    ts: "2026-09-04T00:00:01Z",
                    argv: ["kubectl", "get", "pods"],
                    exitCode: 0,
                    durationMs: 9,
                    tool: "claude"
                ),
            ]
        )
        try HabitRoomFixture.linkTool(in: room, name: "kubectl")
        let exec = SpyExec(log: OrderLog())
        let verdict = try await makeSimulator(
            store: HabitStore(),
            capabilities: MapCapabilityLookup(dryRun: ["safe-cli": ["status"]]),
            exec: exec
        ).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(verdict.passed)
        XCTAssertEqual(verdict.steps.map(\.mode), [.executed, .compared])
        XCTAssertEqual(verdict.steps.map(\.habit), ["safe-cli status", "kubectl get pods"])
        XCTAssertEqual(exec.calls, [
            ["safe-cli", "status", "--dry-run"],
            ["kubectl", "--help"],
        ])
    }

    func testAgentCandidateIsSkippedAndPasses() async throws {
        room = try HabitRoomFixture.makeRoom(
            snapshot: "healthy\n",
            termLog: "healthy\n",
            candidates: [
                HabitCandidate(
                    ts: "2026-09-04T00:00:00Z",
                    argv: ["claude", "-p", "continue the room work"],
                    exitCode: 0,
                    durationMs: 12,
                    tool: "claude"
                ),
            ]
        )
        let log = OrderLog()
        let exec = SpyExec(log: log)
        let ledger = SpyLedger(log: log)
        let verdict = try await makeSimulator(
            store: HabitStore(),
            exec: exec,
            ledger: ledger
        ).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(verdict.passed)
        XCTAssertEqual(verdict.steps.count, 1)
        XCTAssertEqual(verdict.steps[0].habit, "claude -p continue the room work")
        XCTAssertEqual(verdict.steps[0].mode, .skipped)
        XCTAssertTrue(verdict.steps[0].ok)
        XCTAssertEqual(verdict.steps[0].reason, HabitCandidateReplay.agentSkipReason)
        XCTAssertEqual(exec.calls, [])
        XCTAssertEqual(exec.closes, [HabitTestIDs.session])
        XCTAssertEqual(ledger.states, ["passed"])
    }

    func testDryRunContractCandidateIsExecuted() async throws {
        room = try HabitRoomFixture.makeRoom(
            snapshot: "healthy\n",
            termLog: "healthy\n",
            candidates: [
                HabitCandidate(
                    ts: "2026-09-04T00:00:00Z",
                    argv: ["safe-cli", "status"],
                    exitCode: 0,
                    durationMs: 8,
                    tool: "claude"
                ),
            ]
        )
        let log = OrderLog()
        let exec = SpyExec(log: log)
        let ledger = SpyLedger(log: log)
        let verdict = try await makeSimulator(
            store: HabitStore(),
            capabilities: MapCapabilityLookup(dryRun: ["safe-cli": ["status"]]),
            exec: exec,
            ledger: ledger
        ).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(verdict.passed)
        XCTAssertEqual(verdict.steps.count, 1)
        XCTAssertEqual(verdict.steps[0].habit, "safe-cli status")
        XCTAssertEqual(verdict.steps[0].mode, .executed)
        XCTAssertTrue(verdict.steps[0].ok)
        XCTAssertFalse(verdict.steps[0].reason.isEmpty)
        XCTAssertEqual(exec.calls, [["safe-cli", "status", "--dry-run"]])
        XCTAssertEqual(ledger.states, ["passed"])
    }

    func testUnlinkedToolCandidateFailsComparedWithReason() async throws {
        room = try HabitRoomFixture.makeRoom(
            snapshot: "healthy\n",
            termLog: "healthy\n",
            candidates: [
                HabitCandidate(
                    ts: "2026-09-04T00:00:00Z",
                    argv: ["ghost-cli", "run"],
                    exitCode: 0,
                    durationMs: 3,
                    tool: "claude"
                ),
            ]
        )
        let log = OrderLog()
        let exec = SpyExec(log: log)
        let ledger = SpyLedger(log: log)
        let verdict = try await makeSimulator(
            store: HabitStore(),
            exec: exec,
            ledger: ledger
        ).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertFalse(verdict.passed)
        XCTAssertEqual(verdict.steps.count, 1)
        XCTAssertEqual(verdict.steps[0].habit, "ghost-cli run")
        XCTAssertEqual(verdict.steps[0].mode, .compared)
        XCTAssertFalse(verdict.steps[0].ok)
        XCTAssertFalse(verdict.steps[0].reason.isEmpty)
        XCTAssertEqual(verdict.reason, verdict.steps[0].reason)
        XCTAssertEqual(exec.calls, [])
        XCTAssertEqual(ledger.states, ["failed"])
    }

    func testDryRunContractGatesExecution() async throws {
        let logText = """
        safe-cli status
        OK
        kubectl get pods
        NAME ready
        healthy
        """
        room = try HabitRoomFixture.makeRoom(snapshot: logText, termLog: logText)
        let store = HabitStore()
        _ = try store.create(
            in: room,
            title: "혼합 절차",
            steps: [
                HabitRoomFixture.step(
                    tool: "safe-cli",
                    command: "status",
                    dryRunSupported: false,
                    expectedPattern: "OK"
                ),
                HabitRoomFixture.step(
                    tool: "kubectl",
                    command: "get",
                    args: ["pods"],
                    dryRunSupported: true,
                    expectedPattern: "ready"
                ),
            ],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        let log = OrderLog()
        let exec = SpyExec(log: log)
        let simulator = makeSimulator(
            store: store,
            capabilities: MapCapabilityLookup(dryRun: ["safe-cli": ["status"]]),
            exec: exec,
            ledger: SpyLedger(log: log),
            amend: SpyAmend()
        )
        let verdict = try await simulator.simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(verdict.passed)
        XCTAssertEqual(exec.calls.count, 1)
        XCTAssertEqual(exec.calls[0], ["safe-cli", "status", "--dry-run"])
        XCTAssertEqual(verdict.steps.map(\.mode), [.executed, .compared])
    }

    func testDeviationWithoutNoteFailsAndNotePasses() async throws {
        let snapshot = "healthy\n"
        room = try HabitRoomFixture.makeRoom(snapshot: snapshot, termLog: snapshot)
        let store = HabitStore()
        let habit = try store.create(
            in: room,
            title: "이탈 절차",
            steps: [
                HabitRoomFixture.step(
                    tool: "missing-cli",
                    command: "run",
                    expectedPattern: "never-seen"
                ),
            ],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        let first = try await makeSimulator(store: store).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertFalse(first.passed)
        XCTAssertEqual(first.steps.first?.ok, false)
        XCTAssertTrue(first.steps.first?.reason.contains("no deviation note") ?? false)

        _ = try DeviationNoteStore().record(
            room: room,
            number: habit.number,
            reason: "도구가 바뀌었다",
            procedure: "missing-cli 대신 다른 CLI"
        )
        let second = try await makeSimulator(store: store).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(second.passed)
        XCTAssertEqual(second.steps.first?.reason, "documented deviation")
    }

    func testPassClosesThenHandoverPassed() async throws {
        let text = "safe-cli status\nOK\nhealthy\n"
        room = try HabitRoomFixture.makeRoom(snapshot: text, termLog: text)
        let store = HabitStore()
        _ = try store.create(
            in: room,
            title: "통과 절차",
            steps: [
                HabitRoomFixture.step(
                    tool: "safe-cli",
                    command: "status",
                    expectedPattern: "OK"
                ),
            ],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        let log = OrderLog()
        let exec = SpyExec(log: log)
        let ledger = SpyLedger(log: log)
        let verdict = try await makeSimulator(
            store: store,
            exec: exec,
            ledger: ledger
        ).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertTrue(verdict.passed)
        XCTAssertEqual(exec.closes, [HabitTestIDs.session])
        XCTAssertEqual(ledger.states, ["passed"])
        XCTAssertEqual(log.events, ["close", "handover:passed"])
    }

    func testFailHandoverThenEscalateOnThird() async throws {
        room = try HabitRoomFixture.makeRoom(
            snapshot: "healthy\n",
            termLog: "healthy\n"
        )
        let store = HabitStore()
        _ = try store.create(
            in: room,
            title: "실패 절차",
            steps: [
                HabitRoomFixture.step(tool: "ghost-cli", command: "run", expectedPattern: "nope"),
            ],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        let log = OrderLog()
        let ledger = SpyLedger(log: log)
        let amend = SpyAmend()
        let simulator = makeSimulator(store: store, ledger: ledger, amend: amend)
        let auth = HabitRoomFixture.authority()
        let first = try await simulator.simulate(
            room: room, against: HabitTestIDs.handoff, by: auth
        )
        XCTAssertFalse(first.passed)
        XCTAssertEqual(ledger.states, ["failed"])
        XCTAssertEqual(amend.ids, [HabitTestIDs.handoff])

        let second = try await simulator.simulate(
            room: room, against: HabitTestIDs.handoff, by: auth
        )
        XCTAssertFalse(second.passed)
        XCTAssertEqual(ledger.states, ["failed", "failed"])
        XCTAssertEqual(amend.ids.count, 2)

        let third = try await simulator.simulate(
            room: room, against: HabitTestIDs.handoff, by: auth
        )
        XCTAssertFalse(third.passed)
        XCTAssertEqual(ledger.states, ["failed", "failed", "failed"])
        XCTAssertEqual(amend.ids.count, 2)
        let notes = try FileManager.default.contentsOfDirectory(
            atPath: HabitFile.notes(in: room).path
        )
        XCTAssertTrue(notes.contains { $0.contains("escalated") })
        let bottleData = try Data(
            contentsOf: HabitFile.handoff(in: room, id: HabitTestIDs.handoff)
        )
        let bottleJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bottleData) as? [String: Any]
        )
        let note = bottleJSON["note"] as? String ?? ""
        XCTAssertTrue(note.contains("escalated"), note)
        let pitfalls = bottleJSON["pitfalls"] as? [String] ?? []
        XCTAssertTrue(pitfalls.contains { $0.contains("escalated") })
    }

    func testVerdictMismatchAloneFails() async throws {
        let text = "safe-cli status\nOK\n"
        room = try HabitRoomFixture.makeRoom(
            snapshot: text,
            termLog: text,
            verdictOutput: "UNIQUE-VERDICT-MISS"
        )
        let store = HabitStore()
        _ = try store.create(
            in: room,
            title: "판정만 어긋남",
            steps: [
                HabitRoomFixture.step(
                    tool: "safe-cli",
                    command: "status",
                    expectedPattern: "OK"
                ),
            ],
            verify: "true",
            createdBy: HabitTestIDs.handoff
        )
        let ledger = SpyLedger(log: OrderLog())
        let verdict = try await makeSimulator(store: store, ledger: ledger).simulate(
            room: room,
            against: HabitTestIDs.handoff,
            by: HabitRoomFixture.authority()
        )
        XCTAssertFalse(verdict.passed)
        XCTAssertFalse(verdict.verdictMatched)
        XCTAssertTrue(verdict.steps.allSatisfy(\.ok))
        XCTAssertEqual(ledger.states, ["failed"])
    }

    private func makeSimulator(
        store: HabitStore,
        capabilities: any CapabilityLookup = MapCapabilityLookup(),
        exec: SpyExec? = nil,
        ledger: SpyLedger? = nil,
        amend: SpyAmend? = nil
    ) -> Simulator {
        let log = OrderLog()
        return Simulator(
            store: store,
            notes: DeviationNoteStore(),
            capabilities: capabilities,
            exec: exec ?? SpyExec(log: log),
            ledger: ledger ?? SpyLedger(log: log),
            handoff: amend ?? SpyAmend()
        )
    }
}
