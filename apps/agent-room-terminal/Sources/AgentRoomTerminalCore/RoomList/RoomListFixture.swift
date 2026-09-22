import Foundation

/// 원장이 비어 있을 때 GUI 가 그리는 예시 방 목록 모델.
public enum RoomListFixture {
    public static let tenantCount = 4
    public static let roomsPerTenant = 3
    public static let childRoomCount = 9

    public static func rooms() -> [RoomSummary] {
        var nodes: [RoomSummary] = []
        nodes.append(commandRoom())
        var standing: [RoomSummary] = []
        for tenantIndex in 0..<tenantCount {
            let tenant = tenantNode(index: tenantIndex)
            nodes.append(tenant)
            for roomIndex in 0..<roomsPerTenant {
                let room = standingRoom(tenant: tenant.id, tenantIndex: tenantIndex, roomIndex: roomIndex)
                nodes.append(room)
                standing.append(room)
            }
        }
        nodes.append(contentsOf: childRooms(from: standing))
        return nodes
    }

    public static func tree() -> [RoomSummary] {
        rooms()
    }

    private static func commandRoom() -> RoomSummary {
        makeNode(Draft(
            id: "cmd",
            parentID: nil,
            kind: .commandRoom,
            title: "command-room",
            status: .occupied,
            wallPreset: "open",
            wallMode: "full",
            excludedToolCount: 0,
            used: 12_000,
            bottles: 0,
            dualOccupant: false
        ))
    }

    private static func tenantNode(index: Int) -> RoomSummary {
        let slugs = ["gujo", "wiki", "ops", "lab"]
        let statuses: [RoomStatus] = [.occupied, .waiting, .planned, .done]
        return makeNode(Draft(
            id: "tenant-\(index)",
            parentID: "cmd",
            kind: .tenant,
            title: "tenant-\(slugs[index])",
            status: statuses[index],
            wallPreset: "toolbelt",
            wallMode: "full",
            excludedToolCount: 0,
            used: 4_000 * (index + 1),
            bottles: 0,
            dualOccupant: false
        ))
    }

    private static func standingRoom(
        tenant: String,
        tenantIndex: Int,
        roomIndex: Int
    ) -> RoomSummary {
        let ordinal = tenantIndex * roomsPerTenant + roomIndex
        let status = RoomStatus.allCases[ordinal % RoomStatus.allCases.count]
        let open = ordinal % 7 == 0
        let hook = ordinal % 5 == 0
        return makeNode(Draft(
            id: "room-\(tenantIndex)-\(roomIndex)",
            parentID: tenant,
            tenantID: tenant,
            kind: .standingRoom,
            title: "room-\(tenantIndex)-\(roomIndex)",
            status: status,
            wallPreset: open ? "open" : "toolbelt",
            wallMode: hook ? "hookOnly" : "full",
            excludedToolCount: ordinal % 4 == 0 ? 2 : 0,
            used: ordinal % 6 == 0 ? nil : 8_000 + ordinal * 100,
            bottles: ordinal % 8 == 0 ? 3 : ordinal % 3,
            dualOccupant: ordinal % 9 == 0
        ))
    }

    private static func childRooms(from standing: [RoomSummary]) -> [RoomSummary] {
        Array(standing.prefix(childRoomCount)).enumerated().map { index, parent in
            makeNode(Draft(
                id: "child-\(index)",
                parentID: parent.id,
                tenantID: parent.tenantID,
                kind: .childRoom,
                title: "child-\(index)",
                status: index % 2 == 0 ? .waiting : .blocked,
                wallPreset: "readOnly",
                wallMode: "full",
                excludedToolCount: 0,
                used: 1_000 + index,
                bottles: 1,
                dualOccupant: false
            ))
        }
    }

    private struct Draft {
        var id: String
        var parentID: String?
        var tenantID: TenantID = "default"
        var kind: RoomKind
        var title: String
        var status: RoomStatus
        var wallPreset: String
        var wallMode: String
        var excludedToolCount: Int
        var used: Int?
        var bottles: Int
        var dualOccupant: Bool
    }

    private static func makeNode(_ draft: Draft) -> RoomSummary {
        var occupants: [RoomOccupant] = []
        let seated = draft.kind.hostsTerminal && draft.status == .occupied
        let showPredecessor = seated || draft.dualOccupant
        if showPredecessor {
            occupants.append(RoomOccupant(handle: "pred-\(draft.id)", isSuccessor: false))
        }
        if draft.dualOccupant {
            occupants.append(RoomOccupant(handle: "succ-\(draft.id)", isSuccessor: true))
        }
        let bottleList = (0..<draft.bottles).map { HandoffNote(id: "bottle-\(draft.id)-\($0)") }
        var node = RoomSummary(
            id: draft.id,
            parentID: draft.parentID,
            tenantID: draft.tenantID,
            kind: draft.kind,
            title: draft.title,
            status: draft.status
        )
        node.wallPreset = draft.wallPreset
        node.wallMode = draft.wallMode
        node.excludedToolCount = draft.excludedToolCount
        node.budget = RoomUsage(used: draft.used, handoffAt: 80_000)
        node.bottles = bottleList
        node.occupants = occupants
        node.roomMarkdown = "# \(draft.title)\n\ntask: fixture work\nverdict: true\n"
        node.habitIndex = "- list rooms"
        node.sessionID = draft.kind.hostsTerminal ? "session-\(draft.id)" : nil
        node.pid = draft.kind.hostsTerminal ? (12000 + abs(draft.id.hashValue) % 8000) : nil
        node.isExample = true
        return node
    }
}
