import Foundation

/// 후임이 전임 습관을 재연한다. dry-run 계약 없는 명령은 실행하지 않는다.
public struct Simulator: Sendable {
    public var store: HabitStore
    public var notes: DeviationNoteStore
    public var capabilities: any CapabilityLookup
    public var exec: any ExecRunning
    public var ledger: any LedgerHandoverSubmitting
    public var handoff: any HandoffAmending
    public var tuning: HabitTuning

    public init(
        store: HabitStore = HabitStore(),
        notes: DeviationNoteStore = DeviationNoteStore(),
        capabilities: any CapabilityLookup,
        exec: any ExecRunning,
        ledger: any LedgerHandoverSubmitting,
        handoff: any HandoffAmending,
        tuning: HabitTuning = .default
    ) {
        self.store = store
        self.notes = notes
        self.capabilities = capabilities
        self.exec = exec
        self.ledger = ledger
        self.handoff = handoff
        self.tuning = tuning
    }

    public func simulate(
        room: URL,
        against handoffID: String,
        by authority: LedgerAuthority
    ) async throws -> SimulationVerdict {
        let bottle = try HabitHandoffSnapshot.load(room: room, id: handoffID)
        let context = try RoomHabitContext.load(room: room)
        let habits = try store.recent(in: room, limit: tuning.recentCount)
        if bottle.habitCandidates.isEmpty && habits.isEmpty {
            try await SimulationFinish.pass(
                room: room,
                bottle: bottle,
                exec: exec,
                ledger: ledger,
                authority: authority
            )
            return SimulationVerdict(
                passed: true,
                steps: [],
                verdictMatched: true,
                reason: "no-habits"
            )
        }
        let steps: [SimulationStepResult]
        if bottle.habitCandidates.isEmpty {
            steps = try HabitReplay.replay(
                habits: habits,
                room: room,
                bottle: bottle,
                capabilities: capabilities,
                exec: exec,
                notes: notes
            )
        } else {
            steps = try HabitReplay.replayCandidates(
                candidates: bottle.habitCandidates,
                room: room,
                bottle: bottle,
                capabilities: capabilities,
                exec: exec
            )
        }
        let verdictMatched = try HabitReplay.matchVerdict(
            context: context,
            room: room,
            bottle: bottle,
            capabilities: capabilities,
            exec: exec
        )
        let passed = HabitCandidateReplay.passedIgnoringSkipped(steps) && verdictMatched
        if passed {
            try await SimulationFinish.pass(
                room: room,
                bottle: bottle,
                exec: exec,
                ledger: ledger,
                authority: authority
            )
        } else {
            try await SimulationFinish.fail(
                room: room,
                handoffID: handoffID,
                bottle: bottle,
                maxBottleSwaps: tuning.maxBottleSwaps,
                notes: notes,
                handoff: handoff,
                ledger: ledger,
                authority: authority
            )
        }
        return SimulationVerdict(
            passed: passed,
            steps: steps,
            verdictMatched: verdictMatched,
            reason: failReason(passed: passed, steps: steps, verdictMatched: verdictMatched)
        )
    }

    private func failReason(
        passed: Bool,
        steps: [SimulationStepResult],
        verdictMatched: Bool
    ) -> String {
        if passed {
            return ""
        }
        if let step = steps.first(where: { $0.mode != .skipped && !$0.ok }) {
            return step.reason
        }
        if !verdictMatched {
            return "verdict mismatch"
        }
        return "failed"
    }
}
