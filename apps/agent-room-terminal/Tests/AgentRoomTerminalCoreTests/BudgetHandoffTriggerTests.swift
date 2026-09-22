import Foundation
import Testing
import RoomKit
@testable import AgentRoomTerminalCore

@Suite("Budget → Handoff Trigger")
struct BudgetHandoffTriggerTests {
    private func makeTempRoom() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("handoff-trigger-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: base.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: base.appendingPathComponent("handoff"),
            withIntermediateDirectories: true
        )
        return base
    }

    @Test("사용량이 handoffAt 에 도달하면 BudgetState 가 handoff-due 를 반환한다")
    func handoffDueWhenThresholdReached() throws {
        let spec = ToolBudgetSpec.claude
        let initialInput = 100_000
        _ = spec.usable(initialInput: initialInput)
        let handoffAt = spec.handoffAt(initialInput: initialInput)

        let state = Budget.compute(
            tool: .claude,
            initialInput: initialInput,
            used: handoffAt,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil,
            spec: spec
        )
        #expect(state.state == .handoffDue)
        #expect(state.suggestsHandoff)
    }

    @Test("사용량이 handoffAt 미만이면 BudgetState 가 ok 를 반환한다")
    func okWhenBelowThreshold() throws {
        let state = Budget.compute(
            tool: .claude,
            initialInput: 100_000,
            used: 10_000,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
        #expect(state.state == .ok)
        #expect(!state.suggestsHandoff)
    }

    @Test("사용량이 usable 이상이면 over 를 반환한다")
    func overWhenExceedsUsable() throws {
        let spec = ToolBudgetSpec.claude
        let initialInput = 100_000
        let usable = spec.usable(initialInput: initialInput)

        let state = Budget.compute(
            tool: .claude,
            initialInput: initialInput,
            used: usable + 1,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil,
            spec: spec
        )
        #expect(state.state == .over)
    }

    @Test("used 가 nil 이면 unknown 을 반환한다")
    func unknownWhenNoUsage() {
        let state = Budget.compute(
            tool: .claude,
            initialInput: 100_000,
            used: nil,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
        #expect(state.state == .unknown)
    }

    @Test("budgetSampled 이벤트에서 used 를 읽어 BudgetState 를 계산할 수 있다")
    func budgetStateFromEvent() throws {
        let roomURL = try makeTempRoom()
        defer { try? FileManager.default.removeItem(at: roomURL) }

        let eventLog = RoomEventLog(roomURL: roomURL)
        try eventLog.append(
            RoomEvent.budgetSampled(used: 500_000, limit: 700_000, estimated: false)
        )

        let result = eventLog.read(since: 0)
        let sampled = result.events.first { $0.kind == RoomEventKind.budgetSampled }
        #expect(sampled != nil)

        let used = sampled?.payload["used"]?.int
        let limit = sampled?.payload["limit"]?.int
        #expect(used == 500_000)
        #expect(limit == 700_000)

        let state = Budget.compute(
            tool: .claude,
            initialInput: 100_000,
            used: used,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
        #expect(state.state != .unknown, "이벤트에서 used 를 가져왔으므로 unknown 이 아니어야 한다")
    }

    @Test("handoffNoted 이벤트가 원장에 기록된다")
    func handoffNotedEventRecorded() throws {
        let roomURL = try makeTempRoom()
        defer { try? FileManager.default.removeItem(at: roomURL) }

        let eventLog = RoomEventLog(roomURL: roomURL)
        try eventLog.append(RoomEvent.handoffNoted(noteID: "test-note-001"))

        let result = eventLog.read(since: 0)
        let noted = result.events.first { $0.kind == RoomEventKind.handoffNoted }
        #expect(noted != nil)
        #expect(noted?.payload["noteID"]?.string == "test-note-001")
    }
}
