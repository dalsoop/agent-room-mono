import Foundation
import RoomKit

public enum RoomAppBorrowError: Error, LocalizedError, Equatable, Sendable {
    case closedRoom
    case noActiveBorrow(bundleID: String)
    case roomMissing(String)

    public var errorDescription: String? {
        switch self {
        case .closedRoom:
            return "closed room refuses borrow (memory)"
        case .noActiveBorrow(let bundleID):
            return "no active borrow for bundle-id \(bundleID)"
        case .roomMissing(let roomID):
            return "room folder not found: \(roomID)"
        }
    }
}

/// RoomPlacementKit 차용 API 거울. 저장은 킷 `RoomAppBorrowStore`(JSONL)에 위임한다.
public protocol RoomAppBorrowing: Sendable {
    func borrow(
        roomURL: URL,
        roomID: String,
        bundleID: String,
        agent: RoomActor,
        now: Date,
        duration: TimeInterval
    ) throws -> RoomAppBorrow

    func renew(
        roomURL: URL,
        roomID: String,
        bundleID: String,
        agent: RoomActor,
        now: Date,
        duration: TimeInterval
    ) throws -> RoomAppBorrow

    func listActive(roomURL: URL, now: Date) throws -> [RoomAppBorrow]
}

public enum RoomAppBorrowJSON {
    public static func object(_ borrow: RoomAppBorrow) throws -> Any {
        try jsonObject(borrow)
    }

    public static func listObject(roomID: String, borrows: [RoomAppBorrow]) throws -> [String: Any] {
        let rows = try borrows.map { try jsonObject($0) }
        return ["roomID": roomID, "borrows": rows]
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
