import Foundation
import os
import XCTest
@testable import AgentRoomTerminalCore

final class RecordingHandoffLedger: HandoffLedgerPort, Sendable {
    private let opsStorage = OSAllocatedUnfairLock(initialState: [HandoffLedgerOp]())
    private let inner: LedgerQueue?

    init(queue: LedgerQueue? = nil) {
        self.inner = queue
    }

    var ops: [HandoffLedgerOp] {
        opsStorage.withLock { $0 }
    }

    func submit(
        _ op: HandoffLedgerOp,
        by authority: LedgerAuthority
    ) async -> LedgerReply {
        opsStorage.withLock { $0.append(op) }
        switch op {
        case .digest:
            return .success(#"{"ok":true,"kind":"digest"}"#)
        case let .occupySuccessor(planID, roomID, occupant, handle, wallMode):
            guard let inner else {
                return .success(#"{"ok":true,"kind":"occupy"}"#)
            }
            return await inner.submit(
                .occupy(
                    planID: planID,
                    roomID: roomID,
                    occupant: occupant,
                    handle: handle,
                    successor: true,
                    wallMode: wallMode
                ),
                by: authority
            )
        }
    }
}

struct FixedSnapshot: DaemonSnapshotting {
    var lines: [String]
    func snapshot(sessionID: String, lines: Int) throws -> [String] {
        Array(self.lines.prefix(lines))
    }
}

final class QueueIDs: HandoffIdentifying, Sendable {
    private let ids = OSAllocatedUnfairLock(initialState: [String]())

    init(_ values: [String]) {
        ids.withLock { $0 = values }
    }

    func nextID() -> String {
        ids.withLock { list in
            if list.isEmpty { return UUID().uuidString.lowercased() }
            return list.removeFirst()
        }
    }
}

struct FrozenClock: BudgetClock {
    var date: Date
    func now() -> Date { date }
}

final class BudgetHandoffTests: XCTestCase {
    var home: URL!
    let plan = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    let parentRoom = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    let childRoom = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("budget-handoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home {
            try FileManager.default.removeItem(at: home)
        }
        try super.tearDownWithError()
    }

    /// (d) 같은 방 3대 + 자식 방 분기 predecessor 사슬.
    func testPredecessorChainThreeGenerationsAndChildBranch() async throws {
        let parentURL = try makeRoomFolder(id: parentRoom, name: "parent")
        let childURL = try makeChildFolder(parent: parentURL, id: childRoom, name: "child")
        try writeNote(in: parentURL, name: "01.md", body: "습관 1번을 건너뜀")
        let ledger = RecordingHandoffLedger()
        let ids = QueueIDs(["bottle-1", "bottle-2", "bottle-3", "bottle-child"])
        let service = HandoffService(
            ledger: ledger,
            daemon: FixedSnapshot(lines: ["$ ls", "ok"]),
            ids: ids,
            clock: FrozenClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let budget = Budget.compute(
            tool: .claude, initialInput: 0, used: 668_000,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        let auth = LedgerAuthority.commandRoom(sessionID: "s1", seatedRoomID: parentRoom)

        let first = try await service.handoff(HandoffRequest(
            roomID: parentRoom,
            roomURL: parentURL,
            planID: plan,
            note: "남은 일: 테스트 통과",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: "agent:claude@macbook#old",
            successorOccupant: "agent:claude@macbook#new1",
            successorHandle: "new1",
            sessionID: "sess-1",
            wallMode: "full",
            authority: auth
        ))
        let second = try await service.handoff(HandoffRequest(
            roomID: parentRoom,
            roomURL: parentURL,
            planID: plan,
            note: "2대",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: "agent:claude@macbook#new1",
            successorOccupant: "agent:claude@macbook#new2",
            successorHandle: "new2",
            sessionID: "sess-2",
            wallMode: "full",
            authority: auth
        ))
        let third = try await service.handoff(HandoffRequest(
            roomID: parentRoom,
            roomURL: parentURL,
            planID: plan,
            note: "3대",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: "agent:claude@macbook#new2",
            successorOccupant: "agent:claude@macbook#new3",
            successorHandle: "new3",
            sessionID: "sess-3",
            wallMode: "full",
            authority: auth
        ))
        let childAuth = LedgerAuthority.commandRoom(
            sessionID: "child",
            seatedRoomID: childRoom
        )
        let childBottle = try await service.handoff(HandoffRequest(
            roomID: childRoom,
            roomURL: childURL,
            planID: plan,
            note: "자식 첫 빈병",
            predecessor: nil,
            parentRoomURL: parentURL,
            tool: .grok,
            budget: Budget.compute(
                tool: .grok, initialInput: 0, used: 10,
                elapsedMinutes: 1, estimatedWorkMinutes: 60
            ),
            occupant: "agent:grok@macbook#c0",
            successorOccupant: "agent:grok@macbook#c1",
            successorHandle: "c1",
            sessionID: "sess-c",
            wallMode: "full",
            authority: childAuth
        ))

        XCTAssertNil(first.predecessor)
        XCTAssertEqual(second.predecessor, first.id)
        XCTAssertEqual(third.predecessor, second.id)
        XCTAssertEqual(childBottle.predecessor, third.id)

        let chain = try service.handoffChain(roomURL: parentURL)
        XCTAssertEqual(chain.count, 4)
        let byID = Dictionary(uniqueKeysWithValues: chain.map { ($0.id, $0) })
        XCTAssertEqual(byID["bottle-1"]?.predecessor, nil)
        XCTAssertEqual(byID["bottle-2"]?.predecessor, "bottle-1")
        XCTAssertEqual(byID["bottle-3"]?.predecessor, "bottle-2")
        XCTAssertEqual(byID["bottle-child"]?.predecessor, "bottle-3")
        XCTAssertEqual(byID["bottle-child"]?.roomID, childRoom)
    }

    /// (g) 원장 큐 요청 순서: digest → occupy --successor.
    func testHandoffSubmitsDigestThenOccupySuccessor() async throws {
        let roomURL = try makeRoomFolder(id: parentRoom, name: "seq")
        let queue = RoomQueue()
        let ledger = RecordingHandoffLedger(queue: queue)
        let service = HandoffService(
            ledger: ledger,
            daemon: FixedSnapshot(lines: ["prompt>"]),
            ids: QueueIDs(["digest-id-1"]),
            clock: FrozenClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let auth = LedgerAuthority.commandRoom(sessionID: "s", seatedRoomID: parentRoom)
        _ = try await service.handoff(HandoffRequest(
            roomID: parentRoom,
            roomURL: roomURL,
            planID: plan,
            note: "끊는다",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .codex,
            budget: Budget.compute(
                tool: .codex, initialInput: 0, used: 207_200,
                elapsedMinutes: 1, estimatedWorkMinutes: 60
            ),
            occupant: "agent:codex@macbook#a",
            successorOccupant: "agent:codex@macbook#b",
            successorHandle: "b",
            sessionID: "sess-a",
            wallMode: "full",
            authority: auth
        ))

        XCTAssertEqual(ledger.ops.count, 2)
        guard case .digest(let digest) = ledger.ops[0] else {
            return XCTFail("first op must be digest, got \(ledger.ops)")
        }
        XCTAssertEqual(digest.id, "digest-id-1")
        XCTAssertEqual(digest.tool, "codex")
        XCTAssertNil(digest.predecessor)
        guard case let .occupySuccessor(_, roomID, occupant, _, _) = ledger.ops[1] else {
            return XCTFail("second op must be occupy successor")
        }
        XCTAssertEqual(roomID, parentRoom)
        XCTAssertEqual(occupant, "agent:codex@macbook#b")
        XCTAssertEqual(queue.submittedRequests.count, 1)
        if case let .occupy(_, occRoomID, occOccupant, _, _, _) = queue.submittedRequests[0] {
            XCTAssertEqual(occRoomID, parentRoom)
            XCTAssertEqual(occOccupant, "agent:codex@macbook#b")
        }
    }

    func testAmendKeepsPredecessorAndDoesNotOccupy() async throws {
        let roomURL = try makeRoomFolder(id: parentRoom, name: "amend")
        try writeNote(in: roomURL, name: "02.md", body: "보강 노트")
        let ledger = RecordingHandoffLedger()
        let service = HandoffService(
            ledger: ledger,
            daemon: FixedSnapshot(lines: ["first"]),
            ids: QueueIDs(["keep-id"]),
            clock: FrozenClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let auth = LedgerAuthority.commandRoom(sessionID: "s", seatedRoomID: parentRoom)
        let budget = Budget.compute(
            tool: .claude, initialInput: 0, used: 10,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        let created = try await service.handoff(HandoffRequest(
            roomID: parentRoom,
            roomURL: roomURL,
            planID: plan,
            note: "초안",
            predecessor: "prev-bottle",
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: "agent:claude@macbook#a",
            successorOccupant: "agent:claude@macbook#b",
            successorHandle: "b",
            sessionID: "sess",
            wallMode: "full",
            authority: auth
        ))
        let opsBeforeAmend = ledger.ops.count
        let amended = try await service.amend(
            bottleID: created.id,
            roomURL: roomURL,
            note: "보강",
            sessionID: "sess",
            budget: budget
        )
        XCTAssertEqual(amended.predecessor, "prev-bottle")
        XCTAssertEqual(amended.id, created.id)
        XCTAssertEqual(amended.amendments.count, 1)
        XCTAssertEqual(ledger.ops.count, opsBeforeAmend)
    }

    func testToolSelectorPicksLargestRemainderAndTreatsUnknownAsUsable() {
        let claude = Budget.compute(
            tool: .claude, initialInput: 0, used: 800_000,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        let grokUnknown = Budget.compute(
            tool: .grok, initialInput: 0, used: nil,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        let codex = Budget.compute(
            tool: .codex, initialInput: 0, used: 1_000,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        let picked = ToolSelector.pick(
            allowed: [.claude, .codex, .grok],
            states: [.claude: claude, .codex: codex, .grok: grokUnknown]
        )
        XCTAssertEqual(picked, .grok)
        let switched = Budget.compute(
            tool: picked!, initialInput: 0, used: 1_000,
            elapsedMinutes: 1, estimatedWorkMinutes: 60
        )
        XCTAssertEqual(switched.window, 500_000)
        XCTAssertEqual(switched.usable, 400_000)
    }

    private func makeRoomFolder(id: String, name: String) throws -> URL {
        let url = home.appendingPathComponent(name, isDirectory: true)
        try RoomDirectoryLayout.create(at: url)
        try Data(#"{"id":"\#(id)"}"#.utf8).write(
            to: url.appendingPathComponent("ROOM.json")
        )
        return url
    }

    private func makeChildFolder(parent: URL, id: String, name: String) throws -> URL {
        let url = parent
            .appendingPathComponent("children", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try RoomDirectoryLayout.create(at: url)
        try Data(#"{"id":"\#(id)"}"#.utf8).write(
            to: url.appendingPathComponent("ROOM.json")
        )
        return url
    }

    private func writeNote(in room: URL, name: String, body: String) throws {
        let notes = room.appendingPathComponent("state/notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data(body.utf8).write(to: notes.appendingPathComponent(name))
    }
}
