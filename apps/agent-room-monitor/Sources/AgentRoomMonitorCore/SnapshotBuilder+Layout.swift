import Foundation

/// 테넌트 건물 레이아웃
extension SnapshotBuilder {
    func warehouseDoor(_ skills: TwinNode, tenant: String) -> TwinNode {
        TwinNode(
            id: "skill-warehouse-\(tenant)",
            name: skills.name,
            icon: skills.icon,
            kind: .warehouse,
            mascot: skills.mascot,
            state: skills.state,
            health: skills.health,
            born: 0,
            tenantID: tenant,
            viewpoint: "first",
            children: skills.children
        )
    }

    /// 홈 선반에는 점유된 자리만. 빈 자리는 자리 존 안에 남겨 두되, 존 카드 자식에서 뺀다.
    func occupiedSeatsZone(_ zone: TwinNode) -> TwinNode {
        let occupied = zone.children.filter { $0.agent != nil }
        let vacant = zone.children.count - occupied.count
        var health = zone.health
        if vacant > 0 {
            health.notes.append("빈 자리 \(vacant) · 존에 들어가서 봄")
        }
        return TwinNode(
            id: zone.id,
            name: zone.name,
            icon: zone.icon,
            kind: zone.kind,
            mascot: zone.mascot,
            state: zone.state,
            health: health,
            born: zone.born,
            tenantID: zone.tenantID,
            children: occupied
        )
    }

    func filterZone(_ zone: TwinNode, tenant: String) -> TwinNode {
        TwinNode(
            id: "\(zone.id)-\(tenant)",
            name: zone.name,
            icon: zone.icon,
            kind: zone.kind,
            mascot: zone.mascot,
            state: zone.state,
            health: zone.health,
            born: zone.born,
            tenantID: tenant,
            children: zone.children.filter { $0.tenantID == tenant }
        )
    }
}
