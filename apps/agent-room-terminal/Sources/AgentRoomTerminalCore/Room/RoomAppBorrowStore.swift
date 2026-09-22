import Foundation
import RoomKit

/// 킷 JSONL 원장에 borrow/renew/list 를 얹은 앱 진입점.
public struct RoomAppBorrowService: RoomAppBorrowing, Sendable {
    public var store: RoomAppBorrowStore

    public init(store: RoomAppBorrowStore = RoomAppBorrowStore()) {
        self.store = store
    }

    public static let live = RoomAppBorrowService()

    public func borrow(
        roomURL: URL,
        roomID: String,
        bundleID: String,
        agent: RoomActor,
        now: Date = Date(),
        duration: TimeInterval = RoomAppBorrow.defaultDuration
    ) throws -> RoomAppBorrow {
        try assertWritable(roomURL: roomURL, roomID: roomID)
        let record = RoomAppBorrow(
            roomID: roomID,
            bundleID: bundleID,
            agent: agent,
            borrowedAt: now,
            duration: duration
        )
        return try append(record, roomURL: roomURL)
    }

    public func renew(
        roomURL: URL,
        roomID: String,
        bundleID: String,
        agent: RoomActor,
        now: Date = Date(),
        duration: TimeInterval = RoomAppBorrow.defaultDuration
    ) throws -> RoomAppBorrow {
        try assertWritable(roomURL: roomURL, roomID: roomID)
        guard var current = latestActive(
            roomURL: roomURL,
            bundleID: bundleID,
            agent: agent,
            now: now
        ) else {
            throw RoomAppBorrowError.noActiveBorrow(bundleID: bundleID)
        }
        current.renew(now: now, duration: duration)
        return try append(current, roomURL: roomURL)
    }

    public func listActive(roomURL: URL, now: Date = Date()) throws -> [RoomAppBorrow] {
        latestByKey(store.read(in: RoomVaultLayout(roomURL: roomURL)))
            .filter { $0.isActive(now: now) }
    }

    private func append(_ record: RoomAppBorrow, roomURL: URL) throws -> RoomAppBorrow {
        do {
            return try store.append(record, in: RoomVaultLayout(roomURL: roomURL))
        } catch RoomEventLogError.memoryRoomFrozen {
            throw RoomAppBorrowError.closedRoom
        }
    }

    private func assertWritable(roomURL: URL, roomID: String, fileManager: FileManager = FileManager()) throws {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: roomURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw RoomAppBorrowError.roomMissing(roomID)
        }
        do {
            try RoomMemoryGuard.assertMutable(roomURL: roomURL)
        } catch RoomEventLogError.memoryRoomFrozen {
            throw RoomAppBorrowError.closedRoom
        }
    }

    private func latestActive(
        roomURL: URL,
        bundleID: String,
        agent: RoomActor,
        now: Date
    ) -> RoomAppBorrow? {
        latestByKey(store.read(in: RoomVaultLayout(roomURL: roomURL)))
            .first { $0.bundleID == bundleID && $0.agent == agent && $0.isActive(now: now) }
    }

    private func latestByKey(_ rows: [RoomAppBorrow]) -> [RoomAppBorrow] {
        var latest: [String: RoomAppBorrow] = [:]
        var order: [String] = []
        for row in rows {
            let key = "\(row.bundleID)\u{1e}\(row.agent.description)"
            if latest[key] == nil {
                order.append(key)
            }
            latest[key] = row
        }
        return order.compactMap { latest[$0] }
    }
}
