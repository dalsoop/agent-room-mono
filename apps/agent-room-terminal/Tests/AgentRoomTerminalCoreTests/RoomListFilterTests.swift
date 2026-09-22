import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomListFilter — 방 목록 필터 및 테넌트 그룹화")
struct RoomListFilterTests {
    @Test("진행 중 필터는 open 또는 occupied phase 방만 남긴다")
    func testActiveFilter() {
        let n1 = RoomSummary(id: "r1", parentID: "tenant:gujo", kind: .standingRoom, title: "room-1", status: .occupied)
        let n2 = RoomSummary(id: "r2", parentID: "tenant:gujo", kind: .standingRoom, title: "room-2", status: .planned)
        let n3 = RoomSummary(id: "r3", parentID: "tenant:wiki", kind: .standingRoom, title: "room-3", status: .open)
        let tile = RoomSummary(id: "tile-1", parentID: "r1", kind: .appTile, title: "tool", status: .occupied)

        let allNodes = [n1, n2, n3, tile]
        let active = RoomListFilter.filter(nodes: allNodes, mode: .active)
        #expect(active.map(\.id) == ["r1", "r3"])
    }

    @Test("전체 필터는 모든 호스팅 방을 포함하되 타일은 제외한다")
    func testAllFilter() {
        let n1 = RoomSummary(id: "r1", parentID: "tenant:gujo", kind: .standingRoom, title: "room-1", status: .occupied)
        let n2 = RoomSummary(id: "r2", parentID: "tenant:gujo", kind: .standingRoom, title: "room-2", status: .planned)
        let tile = RoomSummary(id: "tile-1", parentID: "r1", kind: .appTile, title: "tool", status: .occupied)

        let allNodes = [n1, n2, tile]
        let all = RoomListFilter.filter(nodes: allNodes, mode: .all)
        #expect(all.map(\.id) == ["r1", "r2"])
    }

    @Test("검색어 필터는 제목, id, task 문구를 대소문자 무관하게 검색한다")
    func testSearchQueryFilter() {
        var n1 = RoomSummary(id: "room-alpha", parentID: "tenant:gujo", kind: .standingRoom, title: "Alpha Room", status: .occupied)
        n1.roomMarkdown = "일: 카탈로그 배포 작업을 진행한다\n완료: true"
        let n2 = RoomSummary(id: "room-beta", parentID: "tenant:gujo", kind: .standingRoom, title: "Beta Room", status: .occupied)

        let nodes = [n1, n2]
        let matchByTask = RoomListFilter.filter(nodes: nodes, mode: .all, query: "카탈로그")
        #expect(matchByTask.map(\.id) == ["room-alpha"])

        let matchById = RoomListFilter.filter(nodes: nodes, mode: .all, query: "BETA")
        #expect(matchById.map(\.id) == ["room-beta"])
    }

    @Test("테넌트별 그룹화는 테넌트 키로 묶여 정렬된다")
    func testGroupByTenant() {
        let n1 = RoomSummary(id: "r1", parentID: "tenant:wiki", kind: .standingRoom, title: "room-wiki", status: .occupied)
        let n2 = RoomSummary(id: "r2", parentID: "tenant:gujo", kind: .standingRoom, title: "room-gujo", status: .occupied)

        let groups = RoomListFilter.groupByTenant(nodes: [n1, n2])
        #expect(groups.count == 2)
        #expect(groups[0].tenant == "gujo")
        #expect(groups[0].rooms.map(\.id) == ["r2"])
        #expect(groups[1].tenant == "wiki")
        #expect(groups[1].rooms.map(\.id) == ["r1"])
    }

    @Test("tenant 노드(kind: .tenant)는 hostsTerminal false 여서 목록에 나오지 않는다")
    func testTenantNodesExcluded() {
        let tenant = RoomSummary(id: "tenant:gujo", parentID: "cmd", kind: .tenant, title: "gujo", status: .occupied)
        let room = RoomSummary(id: "r1", parentID: "tenant:gujo", kind: .standingRoom, title: "room-1", status: .occupied)
        let cmd = RoomSummary(id: "cmd", kind: .commandRoom, title: "command-room", status: .occupied)

        let all = RoomListFilter.filter(nodes: [cmd, tenant, room], mode: .all)
        #expect(all.map(\.id) == ["cmd", "r1"])
        #expect(!all.contains(where: { $0.kind == .tenant }))
    }

    @Test("displayName 은 작업 한 문장 앞 30자를 낸다")
    func testDisplayName() {
        var n = RoomSummary(id: "r1", parentID: "tenant:gujo", kind: .standingRoom, title: "original-title", status: .occupied)
        #expect(RoomListFilter.displayName(for: n) == "original-title")

        n.roomMarkdown = "일: 123456789012345678901234567890EXTRA\n완료: true"
        #expect(RoomListFilter.displayName(for: n) == "123456789012345678901234567890")
    }

    @Test("물리 디스크 경로, node.path, node.id, node.roomMarkdown 기반 부모 테넌트 역추적 복원")
    func testTenantRestoration() {
        // 1. node.path 기반 복원
        var n1 = RoomSummary(id: "r1", parentID: nil, tenantID: "default", kind: .standingRoom, title: "room-1", status: .occupied)
        n1.path = "/Users/jeonghan/.tenants/personal/rooms/L1/room-1"
        #expect(RoomListFilter.tenantName(for: n1) == "personal")

        // 2. node.id 경로 문자열 기반 복원
        let n2 = RoomSummary(
            id: ".tenants/gujo/rooms/L1/room-2", parentID: nil, tenantID: "",
            kind: .standingRoom, title: "room-2", status: .occupied
        )
        #expect(RoomListFilter.tenantName(for: n2) == "gujo")

        // 3. node.roomMarkdown 메타데이터(테넌트:) 기반 복원
        var n3 = RoomSummary(
            id: "r3", parentID: nil, tenantID: "default",
            kind: .standingRoom, title: "room-3", status: .occupied
        )
        n3.roomMarkdown = "일: 정산 작업\n테넌트: finance\n완료: false"
        #expect(RoomListFilter.tenantName(for: n3) == "finance")

        // 4. node.roomMarkdown 내 경로 포함 기반 복원
        var n4 = RoomSummary(
            id: "r4", parentID: nil, tenantID: "default",
            kind: .standingRoom, title: "room-4", status: .occupied
        )
        n4.roomMarkdown = "작업: 배치\n경로: /Users/x/.tenants/ops/rooms/r4"
        #expect(RoomListFilter.tenantName(for: n4) == "ops")

        // 5. 기본값 fallback (아무 경로/정보도 없을 때)
        let n5 = RoomSummary(id: "r5-no-info", parentID: nil, tenantID: "default", kind: .standingRoom, title: "room-5", status: .occupied)
        #expect(RoomListFilter.tenantName(for: n5) == "default")
    }

    @Test("한글 방 이름(NFD: 부엉이) 및 검색 쿼리(NFC: 부엉이) 유니코드 정규화 일치 검증")
    func testUnicodeNFCHangulSearch() {
        // NFD (macOS APFS 파일명 형태: 자모 분리)
        let nfcOwl = "부엉이"
        let nfdOwl = nfcOwl.decomposedStringWithCanonicalMapping // "부엉이" (NFD)

        let nfcCat = "고양이"
        let nfdCat = nfcCat.decomposedStringWithCanonicalMapping // "고양이" (NFD)

        let nfcDog = "강아지"
        let nfdDog = nfcDog.decomposedStringWithCanonicalMapping // "강아지" (NFD)

        var n1 = RoomSummary(id: "owl-room", parentID: "tenant:personal", kind: .standingRoom, title: nfdOwl, status: .occupied)
        n1.roomMarkdown = "일: \(nfdCat) 모니터링"

        let n2 = RoomSummary(id: "dog-room", parentID: "tenant:personal", kind: .standingRoom, title: nfcDog, status: .occupied)

        let nodes = [n1, n2]

        // 1. NFC 완성형 검색어로 NFD 분리형 방 이름 검색 성공
        let matchNFC = RoomListFilter.filter(nodes: nodes, mode: .all, query: nfcOwl)
        #expect(matchNFC.map(\.id) == ["owl-room"])

        // 2. NFD 검색어로 NFD 방 이름 검색 성공
        let matchNFD = RoomListFilter.filter(nodes: nodes, mode: .all, query: nfdOwl)
        #expect(matchNFD.map(\.id) == ["owl-room"])

        // 3. NFC 완성형("고양이") 검색어로 NFD 작업 마크다운 검색 성공
        let matchTask = RoomListFilter.filter(nodes: nodes, mode: .all, query: nfcCat)
        #expect(matchTask.map(\.id) == ["owl-room"])

        // 4. NFD 검색어로 NFC 완성형("강아지") 방 이름 검색 성공
        let matchDog = RoomListFilter.filter(nodes: nodes, mode: .all, query: nfdDog)
        #expect(matchDog.map(\.id) == ["dog-room"])

        // 5. displayName도 NFC 정규화된 형태를 반환
        #expect(RoomListFilter.displayName(for: n1) == "고양이 모니터링")
    }
}

@Suite("RoomOpenPipelinePure — 세션 재사용 필터 검증")
struct RoomOpenPipelinePureTests {
    @Test("종료되었거나 복구된 세션은 재사용하지 않고 살아있는 세션만 재사용한다")
    func testReusedSessionIDFiltersDeadAndRecovered() {
        let room = "/tmp/rooms/room-a"
        let sessions = [
            RoomListedSession(sessionID: "s-dead", roomDir: room, exitCode: 0, recovered: false),
            RoomListedSession(sessionID: "s-recovered", roomDir: room, exitCode: nil, recovered: true),
            RoomListedSession(sessionID: "s-alive", roomDir: room, exitCode: nil, recovered: false),
        ]

        let chosen = RoomOpenPipelinePure.reusedSessionID(
            occupied: true,
            roomPath: room,
            sessions: sessions
        )
        #expect(chosen == "s-alive")
    }

    @Test("preferRole이 매칭되더라도 excluding에 해당하면 제외하고 다른 세션을 선택하거나 nil을 반환한다")
    func testReusedSessionIDExcludesBeforePreferRole() {
        let room = "/tmp/rooms/room-a"
        let sessions = [
            RoomListedSession(sessionID: "s-excluded", roomDir: room, sessionRole: "successor", exitCode: nil, recovered: false),
            RoomListedSession(sessionID: "s-fallback", roomDir: room, sessionRole: "predecessor", exitCode: nil, recovered: false),
        ]

        let chosen = RoomOpenPipelinePure.reusedSessionID(
            occupied: true,
            roomPath: room,
            sessions: sessions,
            preferRole: "successor",
            excluding: "s-excluded"
        )
        #expect(chosen == "s-fallback")

        let none = RoomOpenPipelinePure.reusedSessionID(
            occupied: true,
            roomPath: room,
            sessions: [
                RoomListedSession(sessionID: "s-excluded", roomDir: room, sessionRole: "successor", exitCode: nil, recovered: false),
            ],
            preferRole: "successor",
            excluding: "s-excluded"
        )
        #expect(none == nil)
    }
}
