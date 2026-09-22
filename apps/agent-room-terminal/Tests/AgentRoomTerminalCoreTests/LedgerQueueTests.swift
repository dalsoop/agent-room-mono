import XCTest
@testable import AgentRoomTerminalCore

final class LedgerQueueTests: XCTestCase {
    private let plan = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    private let room = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    private let child = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
    private let foreign = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"

    func testHundredConcurrentRequestsPreserveSubmitOrderAndStaySerial() async {
        let queue = RoomQueue()
        let auth = RoomAuthority.commandRoom(sessionID: "s", seatedRoomID: room)

        var tasks: [Task<RoomReply, Never>] = []
        tasks.reserveCapacity(100)
        for index in 0..<100 {
            let occupant = "agent:grok@macbook#\(index)"
            let request = RoomRequest.occupy(
                planID: plan,
                roomID: room,
                occupant: occupant,
                handle: String(index),
                successor: false,
                wallMode: "full"
            )
            tasks.append(Task {
                await queue.submit(request, by: auth)
            })
            let enqueueWaitLimit = 100_000
            var spins = 0
            while queue.queuedCount < index + 1, spins < enqueueWaitLimit {
                await Task.yield()
                spins += 1
            }
        }

        var replies: [RoomReply] = []
        replies.reserveCapacity(100)
        for task in tasks {
            replies.append(await task.value)
        }

        XCTAssertEqual(replies.count, 100)
        XCTAssertTrue(replies.allSatisfy(\.ok))
        XCTAssertEqual(queue.submittedRequests.count, 100)
        let occupants = queue.submittedRequests.compactMap { req -> String? in
            if case let .occupy(_, _, occupant, _, _, _) = req { return occupant }
            return nil
        }
        XCTAssertEqual(occupants, (0..<100).map { "agent:grok@macbook#\($0)" })
    }

    func testForeignRoomRejectedChildAllowedCommandRoomBypasses() async {
        let queue = RoomQueue()
        let seated = RoomAuthority(
            sessionID: "child-session",
            seatedRoomID: room,
            childRoomIDs: [child],
            scope: .room
        )

        let foreignReply = await queue.submit(
            .occupy(
                planID: plan,
                roomID: foreign,
                occupant: "agent:grok@macbook",
                handle: "s",
                successor: false,
                wallMode: "full"
            ),
            by: seated
        )
        XCTAssertEqual(foreignReply.error, .foreignRoom)
        XCTAssertFalse(foreignReply.ok)
        XCTAssertEqual(queue.submittedRequests.count, 0)

        let childReply = await queue.submit(
            .handover(planID: plan, roomID: child, state: "passed"),
            by: seated
        )
        XCTAssertTrue(childReply.ok)
        XCTAssertEqual(queue.submittedRequests.count, 1)

        let ownReply = await queue.submit(
            .tick(planID: plan, roomID: room, workdir: "/tmp/work"),
            by: seated
        )
        XCTAssertTrue(ownReply.ok)
        XCTAssertEqual(queue.submittedRequests.count, 2)

        let command = RoomAuthority.commandRoom(sessionID: "cmd", seatedRoomID: room)
        let bypass = await queue.submit(
            .occupy(
                planID: plan,
                roomID: foreign,
                occupant: "agent:claude@macbook",
                handle: "cmd",
                successor: false,
                wallMode: "hookOnly"
            ),
            by: command
        )
        XCTAssertTrue(bypass.ok)
        XCTAssertEqual(queue.submittedRequests.count, 3)
    }

    func testOccupyHandoverTickSpawnRoomRecordsSubmitted() async throws {
        let queue = RoomQueue()
        let auth = RoomAuthority(
            sessionID: "sess-1",
            seatedRoomID: room,
            childRoomIDs: [],
            scope: .room
        )

        try await queue.recordOccupancy(
            plan: plan,
            room: room,
            occupant: "agent:claude@macbook#sess-1",
            session: "sess-1",
            wallMode: "full",
            by: auth
        )
        try await queue.recordClose(plan: plan, workdir: "/tmp/room-work", by: auth)
        let spawned = try await queue.spawnChild(
            task: "일 한 문장",
            verify: "true",
            handle: "부엉이",
            occupant: "agent:grok@macbook",
            workdir: "/tmp/child",
            tenant: "tenant:gujo",
            by: auth
        )
        XCTAssertFalse(spawned.isEmpty)

        let handover = await queue.submit(
            .handover(planID: plan, roomID: room, state: "simulating"),
            by: auth
        )
        XCTAssertTrue(handover.ok)
        XCTAssertEqual(queue.submittedRequests.count, 4)
    }

    func testShortPlanIDRejectedWithoutRunningCLI() async {
        let queue = RoomQueue()
        let auth = RoomAuthority.commandRoom(sessionID: "s", seatedRoomID: room)
        let reply = await queue.submit(
            .tick(planID: "abcdabcd", roomID: room, workdir: nil),
            by: auth
        )
        XCTAssertEqual(reply.error, .invalidPlanID)
        XCTAssertEqual(queue.submittedRequests.count, 0)
    }

    func testZeroDeadLedgerReferencesInSources() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourcesURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            XCTFail("Failed to enumerate Sources directory")
            return
        }

        var violations: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            if content.contains("LedgerVacate") {
                violations.append("LedgerVacate found in \(fileURL.lastPathComponent)")
            }
            if content.contains("LedgerCommandRunning") {
                violations.append("LedgerCommandRunning found in \(fileURL.lastPathComponent)")
            }
            if content.contains("ledgerArgv") || content.contains("LedgerArgv") {
                violations.append("LedgerArgv found in \(fileURL.lastPathComponent)")
            }
        }
        XCTAssertTrue(violations.isEmpty, "Found dead ledger references in Sources: \(violations)")
    }
}
