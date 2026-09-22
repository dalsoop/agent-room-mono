import Foundation

enum SimulationFinish {
    static func pass(
        room: URL,
        bottle: HabitHandoffSnapshot,
        exec: any ExecRunning,
        ledger: any LedgerHandoverSubmitting,
        authority: LedgerAuthority
    ) async throws {
        try exec.closeSession(sessionID: bottle.sessionID)
        try await handover(
            bottle: bottle,
            state: HandoffSimulationLedgerState.passed,
            ledger: ledger,
            authority: authority
        )
        let eventLog = RoomEventLog(roomURL: room)
        do {
            _ = try eventLog.append(RoomEvent.vacated(reason: "predecessor session closed upon handoff pass", by: "simulator"))
            if !bottle.successorOccupant.isEmpty {
                _ = try eventLog.append(RoomEvent.occupied(agent: bottle.successorOccupant, sessionID: bottle.successorHandle, by: "simulator"))
            }
        } catch {
            fputs("warning: simulation event failed: \(error)\n", stderr)
        }
        let specURL = room.appendingPathComponent("spec.json")
        do {
            let data = try Data(contentsOf: specURL)
            guard var json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            json["handoverState"] = "passed"
            if !bottle.successorOccupant.isEmpty {
                json["occupant"] = bottle.successorOccupant
            }
            json["successorOccupant"] = ""
            json["successorSession"] = ""
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: specURL)
        } catch {
            fputs("warning: simulation spec update failed: \(error)\n", stderr)
        }
    }

    static func fail(
        room: URL,
        handoffID: String,
        bottle: HabitHandoffSnapshot,
        maxBottleSwaps: Int,
        notes: DeviationNoteStore,
        handoff: any HandoffAmending,
        ledger: any LedgerHandoverSubmitting,
        authority: LedgerAuthority
    ) async throws {
        let attempts = try SimulateAttempts.increment(room: room, handoffID: handoffID)
        if attempts > maxBottleSwaps {
            _ = try notes.writeEscalation(room: room, handoffID: handoffID)
            let reason = HandoffSimulationLedgerState.escalationNote(handoffID: handoffID)
            try HandoffIO.appendDigestNote(
                id: handoffID,
                in: room,
                note: reason,
                pitfall: reason
            )
            try await handover(
                bottle: bottle,
                state: HandoffSimulationLedgerState.fromSimulation("escalated"),
                ledger: ledger,
                authority: authority
            )
            return
        }
        try await handover(
            bottle: bottle,
            state: HandoffSimulationLedgerState.failed,
            ledger: ledger,
            authority: authority
        )
        _ = try notes.writeAmendRequest(room: room, handoffID: handoffID)
        try handoff.amend(room: room, handoffID: handoffID)
    }

    private static func handover(
        bottle: HabitHandoffSnapshot,
        state: String,
        ledger: any LedgerHandoverSubmitting,
        authority: LedgerAuthority
    ) async throws {
        let reply = await ledger.submitHandover(
            planID: bottle.planID,
            roomID: bottle.roomID,
            state: state,
            by: authority
        )
        if !reply.ok {
            throw HabitError.handoverFailed
        }
    }
}
