import Foundation

public enum RoomActionError: Error, Sendable, Equatable {
    case notAvailable(String)
}

/// GUI 가 부르는 방 명령 표면. 실구현은 `CoreRoomActions`, 픽스처는 `RecordingRoomActions`.
public protocol RoomActions: Sendable {
    func openRoom(id: String) async throws
    func closeRoom(id: String) async throws
    func handoff(roomID: String) async throws
    func simulate(roomID: String) async throws
    func showHabits(roomID: String) async throws
}

public struct RecordingRoomActions: RoomActions, Sendable {
    public struct Log: Sendable, Equatable {
        public var op: String
        public var roomID: String
        public init(op: String, roomID: String) {
            self.op = op
            self.roomID = roomID
        }
    }

    private let sink: @Sendable (Log) -> Void

    public init(sink: @escaping @Sendable (Log) -> Void = { _ in }) {
        self.sink = sink
    }

    public func openRoom(id: String) async throws {
        sink(Log(op: "open", roomID: id))
    }

    public func closeRoom(id: String) async throws {
        sink(Log(op: "close", roomID: id))
    }

    public func handoff(roomID: String) async throws {
        sink(Log(op: "handoff", roomID: roomID))
    }

    public func simulate(roomID: String) async throws {
        sink(Log(op: "simulate", roomID: roomID))
    }

    public func showHabits(roomID: String) async throws {
        sink(Log(op: "habits", roomID: roomID))
    }
}
