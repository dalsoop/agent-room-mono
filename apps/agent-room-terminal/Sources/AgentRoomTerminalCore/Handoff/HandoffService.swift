import Foundation
import RoomKit

public struct HandoffService: Sendable {
    public var ledger: (any HandoffLedgerPort)?
    public var daemon: any DaemonSnapshotting
    public var ids: any HandoffIdentifying
    public var clock: any BudgetClock

    public init(
        ledger: (any HandoffLedgerPort)? = nil,
        daemon: any DaemonSnapshotting,
        ids: any HandoffIdentifying = UUIDHandoffIDs(),
        clock: any BudgetClock = SystemBudgetClock()
    ) {
        self.ledger = ledger
        self.daemon = daemon
        self.ids = ids
        self.clock = clock
    }

    @discardableResult
    public func handoff(_ request: HandoffRequest) async throws -> HandoffBottle {
        let bottle = try makeBottle(request)
        try HandoffIO.write(bottle, in: request.roomURL)
        try await submitDigestThenOccupy(bottle: bottle, request: request)
        return bottle
    }

    @discardableResult
    public func amend(
        bottleID: String,
        roomURL: URL,
        note: String,
        sessionID: String,
        budget: BudgetState,
        snapshotLines: Int = 100
    ) async throws -> HandoffBottle {
        var bottle = try HandoffIO.read(id: bottleID, in: roomURL)
        let snapshot = try daemon.snapshot(sessionID: sessionID, lines: snapshotLines)
        let notes = try HandoffIO.habitNotes(in: roomURL)
        let amendment = HandoffAmendment(
            ts: HandoffJSON.iso(clock.now()),
            note: note,
            habitNotes: notes,
            terminalSnapshot: snapshot
        )
        bottle.amendments.append(amendment)
        bottle.habitNotes = notes
        bottle.terminalSnapshot = snapshot
        bottle.budget = budget
        bottle.note = note
        try HandoffIO.write(bottle, in: roomURL)
        return bottle
    }

    public func handoffChain(roomURL: URL) throws -> [HandoffLink] {
        var links: [HandoffLink] = []
        try collectLinks(roomURL: roomURL, fallbackID: roomURL.lastPathComponent, into: &links)
        return links
    }

    public static func readBottle(id: String, in roomURL: URL) throws -> HandoffBottle {
        try HandoffIO.read(id: id, in: roomURL)
    }

    private func makeBottle(_ request: HandoffRequest) throws -> HandoffBottle {
        let predecessor = try HandoffIO.resolvePredecessor(
            requested: request.predecessor,
            roomURL: request.roomURL,
            parentRoomURL: request.parentRoomURL
        )
        let snapshot = try daemon.snapshot(
            sessionID: request.sessionID,
            lines: request.snapshotLines
        )
        let notes = try HandoffIO.habitNotes(in: request.roomURL)
        let parsed = HandoffDigest.apply(arguments: CommandLine.arguments)
        let remaining = parsed.remaining.isEmpty ? [request.note] : parsed.remaining
        let evidence = HandoffTranscriptMiner.collect(
            roomURL: request.roomURL,
            tool: request.tool
        )
        var bottle = HandoffBottle(
            id: ids.nextID(),
            roomID: request.roomID,
            predecessor: predecessor,
            tool: request.tool.rawValue,
            note: request.note,
            budget: request.budget,
            createdAt: HandoffJSON.iso(clock.now()),
            remainingWork: remaining.joined(separator: "\n")
        )
        bottle.habitNotes = notes
        bottle.terminalSnapshot = snapshot
        bottle.pitfalls = parsed.pitfalls
        bottle.decisions = parsed.decisions
        bottle.remaining = remaining
        bottle.sessionID = request.sessionID
        bottle.planID = request.planID
        bottle.successorOccupant = request.successorOccupant
        bottle.successorHandle = request.successorHandle
        bottle.snapshot = snapshot.joined(separator: "\n")
        bottle.habitCandidates = habitCandidates(in: request.roomURL)
        bottle.evidence = evidence
        return bottle
    }

    private func habitCandidates(in roomURL: URL) -> [HabitCandidate] {
        do {
            return try HabitCandidateStore.recent(
                in: roomURL, limit: HabitCandidateStore.defaultHandoffLimit
            )
        } catch {
            // 후보 파일이 없어도 빈병 쓰기는 막지 않는다.
            return []
        }
    }

    private func submitDigestThenOccupy(
        bottle: HandoffBottle,
        request: HandoffRequest
    ) async throws {
        let eventLog = RoomEventLog(roomURL: request.roomURL)
        _ = try eventLog.append(RoomEvent.handoffNoted(noteID: bottle.id, by: "agent"))
        var bottlesCount = 1
        do {
            bottlesCount = try HandoffIO.loadBottles(in: request.roomURL).count
        } catch {
            bottlesCount = 1
        }
        do {
            _ = try eventLog.append(RoomEvent.bottleSwappedEvent(bottleIndex: bottlesCount, by: "handoff"))
        } catch {
            fputs("warning: failed to append bottleSwapped event: \(error)\n", stderr)
        }
        updateRoomSpecAfterHandoff(roomURL: request.roomURL, request: request, bottleIndex: bottlesCount)
        if let ledger {
            let digestReply = await ledger.submit(.digest(bottle.digest), by: request.authority)
            try unwrap(digestReply)
            let occupyReply = await ledger.submit(
                .occupySuccessor(
                    planID: request.planID,
                    roomID: request.roomID,
                    occupant: request.successorOccupant,
                    handle: request.successorHandle,
                    wallMode: request.wallMode
                ),
                by: request.authority
            )
            try unwrap(occupyReply)
        }
    }

    private func updateRoomSpecAfterHandoff(
        roomURL: URL,
        request: HandoffRequest,
        bottleIndex: Int
    ) {
        let specURL = roomURL.appendingPathComponent("spec.json")
        do {
            let data = try Data(contentsOf: specURL)
            guard var json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            json["handoverState"] = "simulating"
            json["successorOccupant"] = request.successorOccupant
            json["successorSession"] = request.successorHandle
            json["bottleSwapCount"] = bottleIndex
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: specURL)
        } catch {
            fputs("warning: failed to update spec.json on handoff: \(error)\n", stderr)
        }
    }

    private func collectLinks(
        roomURL: URL,
        fallbackID: String,
        into links: inout [HandoffLink]
    ) throws {
        let roomID = try HandoffIO.roomID(at: roomURL, fallback: fallbackID)
        for bottle in try HandoffIO.loadBottles(in: roomURL) {
            links.append(HandoffLink(
                id: bottle.id,
                roomID: roomID,
                predecessor: bottle.predecessor
            ))
        }
        try collectChildLinks(roomURL: roomURL, into: &links)
    }

    private func collectChildLinks(
        roomURL: URL,
        into links: inout [HandoffLink]
    ) throws {
        let children = roomURL.appendingPathComponent("children", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: children.path) else { return }
        let names = try fm.contentsOfDirectory(atPath: children.path).sorted()
        for name in names {
            let child = children.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            try collectLinks(roomURL: child, fallbackID: name, into: &links)
        }
    }

    private func unwrap(_ reply: LedgerReply) throws {
        if let error = reply.error { throw HandoffError.ledgerFailed(error) }
        guard reply.ok else { throw HandoffError.ledgerFailed(.jsonMissing) }
    }
}
