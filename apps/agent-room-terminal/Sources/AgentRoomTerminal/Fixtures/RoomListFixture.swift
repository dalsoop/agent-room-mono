import AgentRoomTerminalCore

/// GUI 픽스처 진입점. 원장이 비면 Core `RoomListFixture.rooms()` 를 그린다.
enum RoomCanvasFixture {
    static func nodes() -> [RoomSummary] {
        RoomListFixture.rooms()
    }
}
