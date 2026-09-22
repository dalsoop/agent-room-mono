import Testing
import Foundation
import CoreGraphics
@testable import AgentRoomTerminalCore

@Suite("RoomCanvasTests — 캔버스 테넌트 필터, 비활성 방 필터, 화면 맞춤 및 실행 상태")
struct RoomCanvasTests {
    private func sampleRooms() -> [RoomSummary] {
        var r1 = RoomSummary(id: "r1", parentID: "tenant:gujo", kind: .standingRoom, title: "Gujo Active Room", status: .occupied)
        r1.sessionID = "sess-1"
        r1.pid = 4321
        r1.occupants = [RoomOccupant(handle: "worker-1", isSuccessor: false)]
        r1.budget = RoomUsage(used: 1200, handoffAt: 80000)

        var r2 = RoomSummary(id: "r2", parentID: "tenant:gujo", kind: .standingRoom, title: "Gujo Dismantled Room", status: .closed)
        r2.roomMarkdown = "상태: dismantled\n완료: true"

        var r3 = RoomSummary(id: "r3", parentID: "tenant:personal", kind: .standingRoom, title: "Personal Active Room", status: .open)
        r3.sessionID = "sess-2"
        r3.pid = 5566
        r3.occupants = [RoomOccupant(handle: "agent:personal", isSuccessor: false)]
        r3.budget = RoomUsage(used: 3500, handoffAt: 40000)

        var r4 = RoomSummary(id: "r4", parentID: "tenant:personal", kind: .standingRoom, title: "Personal Abandoned Room", status: .exited)
        r4.roomMarkdown = "상태: abandoned\n탈출: 사유 없음"

        let r5 = RoomSummary(id: "r5", parentID: "tenant:ranode", kind: .standingRoom, title: "Ranode Planned Room", status: .planned)

        let tile = RoomSummary(id: "tile-1", parentID: "r1", kind: .appTile, title: "tool", status: .occupied)

        return [r1, r2, r3, r4, r5, tile]
    }

    @Test("비활성 방(dismantled/abandoned/closed/exited) 판별 로직 검증")
    func testInactiveDetection() {
        let rooms = sampleRooms()
        let activeGujo = rooms.first { $0.id == "r1" }!
        let dismantledGujo = rooms.first { $0.id == "r2" }!
        let abandonedPersonal = rooms.first { $0.id == "r4" }!
        let plannedRanode = rooms.first { $0.id == "r5" }!

        #expect(!RoomCanvasFilter.isInactive(room: activeGujo))
        #expect(RoomCanvasFilter.isInactive(room: dismantledGujo))
        #expect(RoomCanvasFilter.isInactive(room: abandonedPersonal))
        #expect(!RoomCanvasFilter.isInactive(room: plannedRanode))
    }

    @Test("비활성 방 숨김 기본값(true) 적용 시 dismantled/abandoned 방 제외")
    func testHideInactiveRoomsFilter() {
        let rooms = sampleRooms()

        // 기본값: hideInactiveRooms = true -> r2, r4 제외, 타일 제외 -> r1, r3, r5 남음
        let filteredDefault = RoomCanvasFilter.filter(rooms: rooms, tenantFilter: "all", hideInactiveRooms: true)
        #expect(filteredDefault.map(\.id) == ["r1", "r3", "r5"])

        // 토글: hideInactiveRooms = false -> r2, r4 포함 -> r1, r2, r3, r4, r5 남음
        let filteredAll = RoomCanvasFilter.filter(rooms: rooms, tenantFilter: "all", hideInactiveRooms: false)
        #expect(filteredAll.map(\.id) == ["r1", "r2", "r3", "r4", "r5"])
    }

    @Test("테넌트 필터 적용 시 해당 테넌트 노드만 선별")
    func testTenantFilter() {
        let rooms = sampleRooms()

        // personal 테넌트만 필터링 (비활성 숨김 기본값 true)
        let personalRooms = RoomCanvasFilter.filter(rooms: rooms, tenantFilter: "personal", hideInactiveRooms: true)
        #expect(personalRooms.map(\.id) == ["r3"])

        // personal 테넌트 + 비활성 포함
        let personalAll = RoomCanvasFilter.filter(rooms: rooms, tenantFilter: "personal", hideInactiveRooms: false)
        #expect(personalAll.map(\.id) == ["r3", "r4"])

        // gujo 테넌트
        let gujoRooms = RoomCanvasFilter.filter(rooms: rooms, tenantFilter: "gujo", hideInactiveRooms: true)
        #expect(gujoRooms.map(\.id) == ["r1"])
    }

    @Test("2D 레이아웃 및 바운딩 박스 계산 검증")
    func testLayoutAndBoundingBox() {
        let rooms = sampleRooms()
        let activeRooms = RoomCanvasFilter.filter(rooms: rooms, tenantFilter: "all", hideInactiveRooms: true)
        let placed = RoomCanvasLayout.layout(rooms: activeRooms)

        #expect(placed.count == activeRooms.count)

        let bbox = RoomCanvasLayout.boundingBox(for: placed)
        #expect(bbox.width > 0)
        #expect(bbox.height > 0)
        #expect(bbox.minX >= 0)
        #expect(bbox.minY >= 0)
    }

    @Test("화면 맞춤(Fit to Screen) 계산 — x≈3000 오프셋 노드도 화면 중앙으로 정확히 정렬")
    func testFitToScreenFarNode() {
        // x≈3000에 배치되어 화면 밖으로 밀렸던 시나리오 재현
        var farRoom = RoomSummary(id: "far-1", parentID: "tenant:personal", kind: .standingRoom, title: "Far Room", status: .occupied)
        farRoom.pid = 9999
        let farCard = CanvasPlacedCard(
            room: farRoom,
            position: CGPoint(x: 3000, y: 1500),
            size: CGSize(width: 260, height: 135)
        )

        let viewport = CGSize(width: 1000, height: 600)
        let transform = RoomCanvasFitCalculator.calculateFit(cards: [farCard], viewport: viewport, padding: 40)

        #expect(transform.scale > 0)
        // 변환 후 farCard의 중심 좌표가 뷰포트 중심(500, 300)과 일치해야 함
        let projectedCenterX = farCard.position.x * transform.scale + transform.offset.x
        let projectedCenterY = farCard.position.y * transform.scale + transform.offset.y

        #expect(abs(projectedCenterX - 500) < 0.01)
        #expect(abs(projectedCenterY - 300) < 0.01)
    }

    @Test("실행 중 방 상태 표시 필드(PID, occupant, budget) 검증")
    func testRunningRoomMetadata() {
        let rooms = sampleRooms()
        let runningRoom = rooms.first { $0.id == "r1" }!

        #expect(runningRoom.pid == 4321)
        #expect(runningRoom.sessionID == "sess-1")
        #expect(runningRoom.occupants.first?.handle == "worker-1")
        #expect(runningRoom.budget.used == 1200)
        #expect(runningRoom.budget.handoffAt == 80000)
        #expect(runningRoom.budget.fraction != nil)
    }
}
