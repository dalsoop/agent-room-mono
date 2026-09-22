import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomFolderLocator — 스캐폴드 홈 하위 스캔 범위 한정")
struct RoomFolderLocatorTests {
    private func createDummyRoomJSON(at dir: URL, id: String, slug: String, tenant: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let doc: [String: Any] = [
            "id": id,
            "slug": slug,
            "tenant": tenant,
            "layoutId": "layout-1",
            "parentRoomID": "",
            "preset": "toolbelt",
            "task": "test",
            "verdict": "true",
            "brief": [],
            "toolbelt": ["test-tool"],
            "walls": ["network": false, "writePaths": []],
            "budget": [
                "window": 1000,
                "trigger": 0.8,
                "initialInput": 0,
                "reservedOutput": 0,
                "usable": 800,
                "handoffAt": 600
            ],
            "excludedTools": []
        ]
        let data = try JSONSerialization.data(withJSONObject: doc)
        try data.write(to: dir.appendingPathComponent("ROOM.json"))
    }

    @Test("rooms/ 및 children/ 아래의 ROOM.json 만 수집하고 비방 폴더는 스캔하지 않는다")
    func scansOnlyRoomsAndChildren() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("locator-test-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let tenantsRoot = temp.appendingPathComponent(".tenants", isDirectory: true)
        try fm.createDirectory(at: tenantsRoot, withIntermediateDirectories: true)

        // 1. 내부/시스템 디렉터리: _base-bin, _daemon, skills 등
        let baseBin = tenantsRoot.appendingPathComponent("_base-bin", isDirectory: true)
        let daemon = tenantsRoot.appendingPathComponent("_daemon", isDirectory: true)
        let personalSkills = tenantsRoot.appendingPathComponent("personal/skills", isDirectory: true)
        let personalWiki = tenantsRoot.appendingPathComponent("personal/wiki", isDirectory: true)
        let personalLibrary = tenantsRoot.appendingPathComponent("personal/Library", isDirectory: true)

        try fm.createDirectory(at: baseBin, withIntermediateDirectories: true)
        try fm.createDirectory(at: daemon, withIntermediateDirectories: true)
        try fm.createDirectory(at: personalSkills, withIntermediateDirectories: true)
        try fm.createDirectory(at: personalWiki, withIntermediateDirectories: true)
        try fm.createDirectory(at: personalLibrary, withIntermediateDirectories: true)

        // 여기에 ROOM.json 이 실수로 있더라도 _ 나 skills/ 는 수집되지 않아야 함
        try createDummyRoomJSON(at: baseBin, id: "bad-base-bin", slug: "base-bin", tenant: "personal")
        try createDummyRoomJSON(at: personalSkills, id: "bad-skills", slug: "skills", tenant: "personal")

        // 2. 정상 방 구조: .tenants/personal/rooms/layout-1/room-a
        let roomA = tenantsRoot.appendingPathComponent("personal/rooms/layout-1/room-a", isDirectory: true)
        try createDummyRoomJSON(at: roomA, id: "room-a-id", slug: "room-a", tenant: "personal")

        // 방 안의 bin/ 과 work/ 폴더 (심링크 또는 파일)
        let roomABin = roomA.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: roomABin, withIntermediateDirectories: true)
        try createDummyRoomJSON(at: roomABin, id: "bad-room-bin", slug: "bin", tenant: "personal")

        // 3. 자식 방: room-a/children/child-1
        let child1 = roomA.appendingPathComponent("children/child-1", isDirectory: true)
        try createDummyRoomJSON(at: child1, id: "child-1-id", slug: "child-1", tenant: "personal")

        // 4. 또 다른 테넌트의 방: .tenants/gujo/rooms/layout-1/room-b
        let roomB = tenantsRoot.appendingPathComponent("gujo/rooms/layout-1/room-b", isDirectory: true)
        try createDummyRoomJSON(at: roomB, id: "room-b-id", slug: "room-b", tenant: "gujo")

        // RoomFolderLocator.walk 검증
        let rooms = try RoomFolderLocator.walk(tenantsRoot)
        let foundIDs = rooms.compactMap { try? RoomDocument.load(from: $0).id }.sorted()

        #expect(foundIDs == ["child-1-id", "room-a-id", "room-b-id"])
    }

    @Test("단일 테넌트 검색 시 해당 테넌트의 rooms/ 만 검색")
    func scansSingleTenantRooms() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("locator-single-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let tenantsRoot = temp.appendingPathComponent(".tenants", isDirectory: true)
        let personalRoom = tenantsRoot.appendingPathComponent("personal/rooms/layout-1/room-p", isDirectory: true)
        let gujoRoom = tenantsRoot.appendingPathComponent("gujo/rooms/layout-1/room-g", isDirectory: true)

        try createDummyRoomJSON(at: personalRoom, id: "p-id", slug: "room-p", tenant: "personal")
        try createDummyRoomJSON(at: gujoRoom, id: "g-id", slug: "room-g", tenant: "gujo")

        let env = ["SWIFT_APP_STATE_ROOT": temp.path]
        let gujoOnly = try RoomFolderLocator.allRooms(tenant: "gujo", environment: env)
        #expect(gujoOnly.count == 1)
        #expect(try RoomDocument.load(from: gujoOnly[0]).id == "g-id")
    }
}
