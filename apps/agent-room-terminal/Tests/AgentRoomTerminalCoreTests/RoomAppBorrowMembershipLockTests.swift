import Foundation
import RoomKit
import XCTest
@testable import AgentRoomTerminalCore

/// Worker 4 lock: Safari borrow/expiry list, closed room → memoryRoomFrozen.
final class RoomAppBorrowMembershipLockTests: XCTestCase {
    private let roomID = "ROOM-A-6B28F76A-6DCE-4A24-836B-E91CF65ACCBC"
    private let safariBundle = "com.apple.Safari"
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let agent = RoomActor.agent(name: "grok", sessionID: "w4-lock")
    private let service = RoomAppBorrowService()
    private var roomURL = URL(fileURLWithPath: "/tmp/w4-placeholder", isDirectory: true)

    override func setUpWithError() throws {
        try super.setUpWithError()
        roomURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("w4-safari-borrow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: roomURL, withIntermediateDirectories: true)
        _ = try RoomEventLog(roomURL: roomURL).append(RoomEvent.created(by: "w4-lock"))
    }

    override func tearDownWithError() throws {
        if let roomURL {
            try? FileManager.default.removeItem(at: roomURL)
        }
        try super.tearDownWithError()
    }

    func testBorrowSafariThenListContainsItUntilExpiry() throws {
        let row = try service.borrow(
            roomURL: roomURL,
            roomID: roomID,
            bundleID: safariBundle,
            agent: agent,
            now: now
        )
        XCTAssertEqual(row.bundleID, safariBundle)
        XCTAssertEqual(row.roomID, roomID)
        XCTAssertEqual(row.status, .active)
        XCTAssertEqual(row.expiresAt.timeIntervalSince(row.borrowedAt), RoomAppBorrow.defaultDuration)
        XCTAssertEqual(RoomAppBorrow.defaultDuration, 300)

        let during = try service.listActive(roomURL: roomURL, now: now)
        XCTAssertEqual(during.map(\.bundleID), [safariBundle])

        let expired = try service.listActive(roomURL: roomURL, now: now.addingTimeInterval(301))
        XCTAssertEqual(expired.map(\.bundleID), [])
        XCTAssertEqual(expired.contains { $0.bundleID == safariBundle }, false)
    }

    func testClosedRoomStoreAppendThrowsMemoryRoomFrozenForSafari() throws {
        _ = try RoomEventLog(roomURL: roomURL).append(RoomEvent.closed(by: "w4-lock"))
        XCTAssertEqual(RoomMemoryGuard.isFrozen(roomURL: roomURL), true)

        let store = RoomAppBorrowStore()
        let borrow = RoomAppBorrow(
            roomID: roomID,
            bundleID: safariBundle,
            agent: agent,
            borrowedAt: now
        )
        XCTAssertThrowsError(try store.append(borrow, in: RoomVaultLayout(roomURL: roomURL))) { error in
            XCTAssertEqual(error as? RoomEventLogError, .memoryRoomFrozen)
        }
        XCTAssertEqual(
            FileManager.default.fileExists(atPath: RoomVaultLayout(roomURL: roomURL).appBorrowsFile.path),
            false
        )

        XCTAssertThrowsError(
            try service.borrow(
                roomURL: roomURL,
                roomID: roomID,
                bundleID: safariBundle,
                agent: agent,
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? RoomAppBorrowError, .closedRoom)
            XCTAssertEqual(
                (error as? RoomAppBorrowError)?.errorDescription?.contains("memory"),
                true
            )
        }
        XCTAssertEqual(try service.listActive(roomURL: roomURL, now: now), [])
    }
}
