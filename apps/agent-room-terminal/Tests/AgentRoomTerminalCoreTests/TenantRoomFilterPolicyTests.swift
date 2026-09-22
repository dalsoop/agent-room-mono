import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("TenantRoomFilterPolicy — 테넌트 루트 제외 및 방 식별자 검증")
struct TenantRoomFilterPolicyTests {

    @Test("테넌트 접두사 식별자 판정 검증")
    func testTenantRootIdentifierDetection() {
        #expect(TenantRoomFilterPolicy.isTenantRootIdentifier("tenant:gujo"))
        #expect(TenantRoomFilterPolicy.isTenantRootIdentifier("tenant:personal"))
        #expect(TenantRoomFilterPolicy.isTenantRootIdentifier("tenant:default"))

        // tenant-audit 처럼 하이픈이 들어간 정상 방 식별자는 테넌트 루트가 아님
        #expect(!TenantRoomFilterPolicy.isTenantRootIdentifier("tenant-audit"))
        #expect(!TenantRoomFilterPolicy.isTenantRootIdentifier("tenant-migration"))
        #expect(!TenantRoomFilterPolicy.isTenantRootIdentifier("room-1"))
        #expect(!TenantRoomFilterPolicy.isTenantRootIdentifier("command-room"))
        #expect(!TenantRoomFilterPolicy.isTenantRootIdentifier("C72B0AF2-5C8E-449C-A6F3-5AB297109A62"))
        #expect(!TenantRoomFilterPolicy.isTenantRootIdentifier(""))
    }

    @Test("방 식별자 및 slug 규약 검증")
    func testRoomIdentifierAndSlugValidation() {
        #expect(!TenantRoomFilterPolicy.isValidRoomIdentifier("tenant:gujo"))
        #expect(!TenantRoomFilterPolicy.isValidRoomIdentifier("tenant:personal"))
        #expect(TenantRoomFilterPolicy.isValidRoomIdentifier("tenant-audit"))
        #expect(TenantRoomFilterPolicy.isValidRoomIdentifier("normal-room"))
        #expect(TenantRoomFilterPolicy.isValidRoomIdentifier("C72B0AF2-5C8E-449C-A6F3-5AB297109A62"))

        #expect(!TenantRoomFilterPolicy.isValidRoomSlug("tenant:gujo"))
        #expect(TenantRoomFilterPolicy.isValidRoomSlug("tenant-audit"))
        #expect(TenantRoomFilterPolicy.isValidRoomSlug("my-room-1"))
        #expect(TenantRoomFilterPolicy.isValidRoomSlug("C72B0AF2-5C8E-449C-A6F3-5AB297109A62"))
    }

    @Test("GUI 목록 노출 가능 방 판정 — 테넌트 루트 노드 및 타일 배제")
    func testIsDisplayableRoom() {
        // 1. 테넌트 루트 노드: 기본 생성 시 budget 토큰 0/한도 1, kind: .tenant
        let tenantNode = RoomSummary(
            id: "tenant:gujo",
            parentID: "command-room",
            kind: .tenant,
            title: "gujo",
            status: .occupied
        )
        #expect(!TenantRoomFilterPolicy.isDisplayableRoom(node: tenantNode))

        // 2. kind 가 standingRoom 이더라도 id 가 tenant 접두사인 경우 방어 배제
        let badIdNode = RoomSummary(
            id: "tenant:personal",
            parentID: "command-room",
            kind: .standingRoom,
            title: "personal",
            status: .occupied
        )
        #expect(!TenantRoomFilterPolicy.isDisplayableRoom(node: badIdNode))

        // 3. title 이 tenant: 접두사인 경우 배제
        let badTitleNode = RoomSummary(
            id: "room-x",
            parentID: "command-room",
            kind: .standingRoom,
            title: "tenant:gujo",
            status: .occupied
        )
        #expect(!TenantRoomFilterPolicy.isDisplayableRoom(node: badTitleNode))

        // 4. 앱 타일 배제
        let tileNode = RoomSummary(
            id: "room-1/tool",
            parentID: "room-1",
            kind: .appTile,
            title: "tool",
            status: .occupied
        )
        #expect(!TenantRoomFilterPolicy.isDisplayableRoom(node: tileNode))

        // 5. 정상 상주 방 허용
        let validRoom = RoomSummary(
            id: "room-1",
            parentID: "tenant:gujo",
            kind: .standingRoom,
            title: "room-1",
            status: .occupied
        )
        #expect(TenantRoomFilterPolicy.isDisplayableRoom(node: validRoom))

        // 6. 정상 자식 방 허용
        let validChild = RoomSummary(
            id: "child-1",
            parentID: "room-1",
            kind: .childRoom,
            title: "child-1",
            status: .open
        )
        #expect(TenantRoomFilterPolicy.isDisplayableRoom(node: validChild))

        // 7. 지휘실 허용
        let commandRoom = RoomSummary(
            id: "command-room",
            parentID: nil,
            kind: .commandRoom,
            title: "command-room",
            status: .occupied
        )
        #expect(TenantRoomFilterPolicy.isDisplayableRoom(node: commandRoom))
    }

    @Test("디렉터리 수준 테넌트 루트 배제 및 유효 방 폴더 판정")
    func testDirectoryFiltering() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tenant-filter-test-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        // 테넌트 루트 디렉터리 (~/.tenants/gujo) - 내부에 rooms/ 가 있음
        let gujoTenantRoot = temp.appendingPathComponent(".tenants/gujo", isDirectory: true)
        let gujoRoomsDir = gujoTenantRoot.appendingPathComponent("rooms", isDirectory: true)
        try fm.createDirectory(at: gujoRoomsDir, withIntermediateDirectories: true)

        // 정상 방 폴더 (~/.tenants/gujo/rooms/L1/room-1)
        let validRoomDir = gujoRoomsDir.appendingPathComponent("L1/room-1", isDirectory: true)
        try fm.createDirectory(at: validRoomDir, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)?.write(to: validRoomDir.appendingPathComponent("ROOM.json"))

        // spec.json 을 가진 정상 방 폴더
        let specRoomDir = gujoRoomsDir.appendingPathComponent("L1/room-2", isDirectory: true)
        try fm.createDirectory(at: specRoomDir, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)?.write(to: specRoomDir.appendingPathComponent("spec.json"))

        // 비방 폴더 (메타데이터 없음)
        let invalidDir = gujoTenantRoot.appendingPathComponent("skills", isDirectory: true)
        try fm.createDirectory(at: invalidDir, withIntermediateDirectories: true)

        #expect(!TenantRoomFilterPolicy.isValidRoomDirectory(url: gujoTenantRoot))
        #expect(!TenantRoomFilterPolicy.isValidRoomDirectory(url: gujoRoomsDir))
        #expect(!TenantRoomFilterPolicy.isValidRoomDirectory(url: invalidDir))
        #expect(TenantRoomFilterPolicy.isValidRoomDirectory(url: validRoomDir))
        #expect(TenantRoomFilterPolicy.isValidRoomDirectory(url: specRoomDir))

        let candidateURLs = [gujoTenantRoot, gujoRoomsDir, validRoomDir, specRoomDir, invalidDir]
        let filteredURLs = TenantRoomFilterPolicy.filterDirectories(urls: candidateURLs)
        #expect(filteredURLs == [validRoomDir, specRoomDir])
    }

    @Test("RoomListFilter 에 테넌트 루트 노드가 혼입되어도 'default' 그룹 방으로 노출되지 않음")
    func testRoomListFilterExcludesTenantRootsFromDefaultGroup() {
        let tenantGujo = RoomSummary(
            id: "tenant:gujo",
            parentID: "command-room",
            kind: .tenant,
            title: "gujo",
            status: .occupied
        )
        let tenantPersonal = RoomSummary(
            id: "tenant:personal",
            parentID: "command-room",
            kind: .tenant,
            title: "personal",
            status: .occupied
        )
        let validRoom = RoomSummary(
            id: "room-alpha",
            parentID: "tenant:gujo",
            kind: .standingRoom,
            title: "Alpha Room",
            status: .occupied
        )

        let nodes = [tenantGujo, tenantPersonal, validRoom]

        // 1. RoomListFilter.filter 검증
        let filtered = RoomListFilter.filter(nodes: nodes, mode: .all)
        #expect(filtered.map(\.id) == ["room-alpha"])
        #expect(!filtered.contains(where: { $0.id == "tenant:gujo" }))
        #expect(!filtered.contains(where: { $0.id == "tenant:personal" }))

        // 2. groupByTenant 검증
        let groups = RoomListFilter.groupByTenant(nodes: filtered)
        #expect(groups.count == 1)
        #expect(groups[0].tenant == "gujo")
        #expect(groups[0].rooms.map(\.id) == ["room-alpha"])
        #expect(!groups.contains(where: { $0.tenant == "default" }))
    }
}
