import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomTreeSource — 실제 방 폴더를 층위 노드로")
struct RoomTreeSourceTests {
    private func makeRoom(root: URL, tenant: String, slug: String, id: String, tools: [String]) throws -> URL {
        let folder = root.appendingPathComponent(".tenants/\(tenant)/rooms/L1/\(slug)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document: [String: Any] = [
            "id": id, "slug": slug, "tenant": "tenant:\(tenant)", "layoutId": "L1",
            "parentRoomID": "", "preset": "toolbelt", "task": "일", "verdict": "true",
            "brief": [], "toolbelt": tools,
            "walls": ["network": true, "writePaths": []],
            "budget": ["window": 10, "trigger": 0.8, "initialInput": 0, "reservedOutput": 0,
                       "usable": 8, "handoffAt": 6],
            "excludedTools": [tools.last ?? ""],
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        try data.write(to: folder.appendingPathComponent("ROOM.json"))
        return folder
    }

    @Test("지휘실·테넌트·방·앱 타일이 층위로 나오고 세션이 있으면 occupied")
    func buildsLayers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-tree-\(UUID().uuidString)", isDirectory: true)
        let a = try makeRoom(root: root, tenant: "gujo", slug: "seller", id: "R1", tools: ["x", "y"])
        _ = try makeRoom(root: root, tenant: "gujo", slug: "buyer", id: "R2", tools: ["z"])
        let snap = try RoomTreeSource.snapshot(
            environment: ["SWIFT_APP_STATE_ROOT": root.path],
            sessionsByRoomDir: [SessionAuthorizer.standardized(a.path): "sess-1"]
        )
        #expect(snap.roomCount == 2)
        let kinds = snap.nodes.map(\.kind)
        #expect(kinds.filter { $0 == .commandRoom }.count == 1)
        #expect(kinds.filter { $0 == .tenant }.count == 1)
        #expect(kinds.filter { $0 == .standingRoom }.count == 2)
        #expect(kinds.filter { $0 == .appTile }.count == 3)
        let seller = try #require(snap.nodes.first { $0.id == "R1" })
        #expect(seller.status == .occupied)
        #expect(seller.sessionID == "sess-1")
        #expect(seller.parentID == "tenant:gujo")
        #expect(seller.excludedToolCount == 1)
        let buyer = try #require(snap.nodes.first { $0.id == "R2" })
        #expect(buyer.status == .planned)
        #expect(snap.nodes.allSatisfy { !$0.isExample })
    }

    @Test("방이 없으면 빈 스냅샷")
    func emptyWhenNoRooms() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-tree-empty-\(UUID().uuidString)", isDirectory: true)
        let snap = try RoomTreeSource.snapshot(environment: ["SWIFT_APP_STATE_ROOT": root.path])
        #expect(snap.nodes.isEmpty)
    }

    @Test("자식 방의 tenantID 가 부모 룸 ID 때문에 유실되지 않고 보존된다")
    func testChildRoomPreservesTenantID() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-tree-child-\(UUID().uuidString)", isDirectory: true)
        _ = try makeRoom(root: root, tenant: "personal", slug: "parent-room", id: "P1", tools: ["x"])

        // Create child room under P1
        let childFolder = root.appendingPathComponent(".tenants/personal/rooms/L1/child-room", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        let childDoc: [String: Any] = [
            "id": "C1", "slug": "child-room", "tenant": "tenant:personal", "layoutId": "L1",
            "parentRoomID": "P1", "preset": "toolbelt", "task": "자식 작업", "verdict": "true",
            "brief": [], "toolbelt": ["y"],
            "walls": ["network": true, "writePaths": []],
            "budget": ["window": 10, "trigger": 0.8, "initialInput": 0, "reservedOutput": 0,
                       "usable": 8, "handoffAt": 6],
            "excludedTools": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: childDoc)
        try data.write(to: childFolder.appendingPathComponent("ROOM.json"))

        let snap = try RoomTreeSource.snapshot(environment: ["SWIFT_APP_STATE_ROOT": root.path])
        let childNode = try #require(snap.nodes.first { $0.id == "C1" })
        #expect(childNode.kind == .childRoom)
        #expect(childNode.parentID == "P1")
        #expect(childNode.tenantID == "tenant:personal")
        #expect(RoomListFilter.tenantName(for: childNode) == "personal")
    }

    @Test("한글 NFD 방 slug 및 tenant 복원 검증")
    func testHangulNFDRoomAndDiskPathTenantRecovery() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-tree-hangul-\(UUID().uuidString)", isDirectory: true)

        // NFD "부엉이" slug
        let nfdSlug = "\u{1107}\u{116E}\u{110B}\u{1165}\u{11BC}\u{110B}\u{1175}"
        let folder = root.appendingPathComponent(".tenants/gujo/rooms/L1/\(nfdSlug)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // ROOM.json with tenant as "default" to test physical path recovery
        let document: [String: Any] = [
            "id": "OWL-1", "slug": nfdSlug, "tenant": "default", "layoutId": "L1",
            "parentRoomID": "", "preset": "toolbelt", "task": "부엉이 관측", "verdict": "true",
            "brief": [], "toolbelt": ["t1"],
            "walls": ["network": true, "writePaths": []],
            "budget": ["window": 10, "trigger": 0.8, "initialInput": 0, "reservedOutput": 0,
                       "usable": 8, "handoffAt": 6],
            "excludedTools": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        try data.write(to: folder.appendingPathComponent("ROOM.json"))

        let snap = try RoomTreeSource.snapshot(environment: ["SWIFT_APP_STATE_ROOT": root.path])
        let owlNode = try #require(snap.nodes.first { $0.id == "OWL-1" })

        // 1. 방 title이 NFC "부엉이"로 정규화되었는지 검증
        #expect(owlNode.title == "부엉이")

        // 2. node.path가 folder.path로 설정되었는지 검증 (표준 경로 일치)
        #expect(SessionAuthorizer.standardized(owlNode.path ?? "") == SessionAuthorizer.standardized(folder.path))
        #expect(owlNode.path?.hasSuffix(".tenants/gujo/rooms/L1/\(nfdSlug)") == true)

        // 3. tenantID가 "default"였어도 물리 디스크 경로(.tenants/gujo/...)로부터 "gujo"로 복원되었는지 검증
        #expect(RoomListFilter.tenantName(for: owlNode) == "gujo")

        // 4. RoomListFilter에서 NFC "부엉이" 쿼리로 검색되는지 검증
        let filtered = RoomListFilter.filter(nodes: snap.nodes, mode: .all, query: "부엉이")
        #expect(filtered.map(\.id).contains("OWL-1"))
    }
}
