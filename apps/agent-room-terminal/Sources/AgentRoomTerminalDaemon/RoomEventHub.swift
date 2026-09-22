import Foundation
import AgentRoomTerminalCore

final class RoomEventHub {
    private let lock = NSLock()
    private var subscribers: [String: [UUID: (RoomEvent) -> Void]] = [:]

    init() {}

    func subscribe(
        roomDir: String,
        onEvent: @escaping (RoomEvent) -> Void
    ) -> (UUID, String) {
        let id = UUID()
        let standardized = SessionAuthorizer.standardized(roomDir)
        lock.lock()
        defer { lock.unlock() }
        subscribers[standardized, default: [:]][id] = onEvent
        return (id, standardized)
    }

    func unsubscribe(id: UUID, roomDir: String) {
        let standardized = SessionAuthorizer.standardized(roomDir)
        lock.lock()
        defer { lock.unlock() }
        subscribers[standardized]?.removeValue(forKey: id)
        if subscribers[standardized]?.isEmpty == true {
            subscribers.removeValue(forKey: standardized)
        }
    }

    func broadcast(roomDir: String, event: RoomEvent) {
        let standardized = SessionAuthorizer.standardized(roomDir)
        lock.lock()
        let listeners: [(RoomEvent) -> Void]
        if let map = subscribers[standardized] {
            listeners = Array(map.values)
        } else {
            listeners = []
        }
        lock.unlock()
        for listener in listeners {
            listener(event)
        }
    }
}
