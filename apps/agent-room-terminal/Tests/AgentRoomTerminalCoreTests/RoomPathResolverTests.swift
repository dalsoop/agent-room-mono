import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomPathResolver — 정본 방 경로 조립")
struct RoomPathResolverTests {
    @Test("기존 방이 없으면 정본 경로 rooms/<roomID> 를 돌려준다")
    func returnsCanonicalPathWhenNoExistingRoom() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-resolve-\(UUID().uuidString)", isDirectory: true)
        let env = ["SWIFT_APP_STATE_ROOT": temp.path]
        let home = temp.path

        let result = RoomPathResolver.resolveRoomURL(
            roomID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            tenant: "tenant:gujo",
            environment: env,
            homeDirectory: home
        )
        #expect(result.path.contains("/gujo/rooms/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        #expect(!result.path.contains("/rooms/layout/"))
    }

    @Test("정본 경로에 방이 있으면 그 경로를 돌려준다")
    func returnsExistingCanonicalPath() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-exist-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        let roomDir = temp.appendingPathComponent(
            ".tenants/gujo/rooms/ROOM-ID-1", isDirectory: true
        )
        try fm.createDirectory(at: roomDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let env = ["SWIFT_APP_STATE_ROOT": temp.path]
        let home = temp.path

        let result = RoomPathResolver.resolveRoomURL(
            roomID: "ROOM-ID-1",
            tenant: "tenant:gujo",
            environment: env,
            homeDirectory: home
        )
        #expect(result.path == roomDir.path)
    }

    @Test("레거시 폴더가 있으면 레거시 경로를 돌려준다")
    func returnsLegacyPathWhenExists() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-legacy-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        let legacyDir = temp.appendingPathComponent(
            ".tenants/gujo/rooms/PLAN-1/seller", isDirectory: true
        )
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        let doc: [String: Any] = [
            "id": "LEGACY-ROOM-ID", "slug": "seller", "tenant": "tenant:gujo",
            "layoutId": "PLAN-1", "parentRoomID": "", "preset": "toolbelt",
            "task": "일", "verdict": "true", "brief": [], "toolbelt": [],
            "walls": ["network": true, "writePaths": []],
            "budget": [
                "window": 10, "trigger": 0.8, "initialInput": 0,
                "reservedOutput": 0, "usable": 8, "handoffAt": 6
            ],
            "excludedTools": []
        ]
        let data = try JSONSerialization.data(withJSONObject: doc)
        try data.write(to: legacyDir.appendingPathComponent("ROOM.json"))
        defer { try? fm.removeItem(at: temp) }

        let env = ["SWIFT_APP_STATE_ROOT": temp.path]
        let home = temp.path

        let result = RoomPathResolver.resolveRoomURL(
            roomID: "LEGACY-ROOM-ID",
            tenant: "tenant:gujo",
            environment: env,
            homeDirectory: home
        )
        let std = { (p: String) in (p as NSString).standardizingPath }
        #expect(std(result.path) == std(legacyDir.path))
    }
}
