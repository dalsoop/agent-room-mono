import Foundation
import LocalizationKit

/// 일하는 방 노드
extension SnapshotBuilder {
    func buildWorkRoomsNode(
        placements: [PlacementDTO],
        blueprints: [BlueprintDTO],
        toolbelts: [String: [String]],
        usage: [String: SkillUsage],
        sessions: [SessionCardDTO],
        seats: [SeatDTO],
        here: String
    ) -> TwinNode {
        let children = placements.map { placement -> TwinNode in
            let born = bornSeconds(placement.createdAt ?? placement.updatedAt)
            let session = sessions.first { card in
                guard let cwd = card.cwd, let work = placement.workdir, !cwd.isEmpty else { return false }
                return cwd == work || cwd.hasPrefix(work) || work.hasPrefix(cwd)
            }
            let seat = seats.first { item in
                guard let work = placement.workdir, let path = item.workdir, !path.isEmpty else { return false }
                let occ = item.occupant ?? ""
                return !occ.isEmpty && (path == work || path.hasPrefix(work) || work.hasPrefix(path))
            }
            let fallbackAgent: TwinAgent? = {
                if let card = session {
                    return TwinAgent(
                        actor: card.tool.map { "agent:\($0)@host" } ?? "session",
                        sessionID: card.sessionId,
                        tool: card.tool,
                        env: card.cwd
                    )
                }
                if let seat, let occ = seat.occupant, !occ.isEmpty {
                    return TwinAgent(actor: occ, tool: occ, model: seat.model, env: seat.workdir)
                }
                return nil
            }()
            let roomChildren = (placement.rooms ?? []).map { room -> TwinNode in
                let bp = blueprints.first(where: { $0.slug == room.blueprintSlug })
                let belt = bp?.toolbelt ?? room.blueprintSlug.flatMap { toolbelts[$0] } ?? []
                var tiles = belt.map { skillTile($0, usage: usage) }
                for path in bp?.walls?.writePaths ?? [] {
                    tiles.append(TwinAttachment(kind: "write", name: path, value: path))
                }
                if let net = bp?.walls?.network {
                    tiles.append(TwinAttachment(kind: "net", name: net ? "net-on" : "net-off", value: net ? "1" : "0"))
                }
                var notes: [String] = []
                if let tenant = placement.tenantID { notes.append(tenant) }
                let agent: TwinAgent? = {
                    if let occ = room.occupant, !occ.isEmpty {
                        return TwinAgent(actor: occ, tool: occ, env: placement.workdir)
                    }
                    return fallbackAgent
                }()
                let lease = placement.workdir.map { path in
                    TwinLease(appName: placement.title ?? URL(fileURLWithPath: path).lastPathComponent, detail: path)
                }
                return TwinNode(
                    id: room.id,
                    name: bp?.title ?? room.blueprintSlug ?? room.id,
                    icon: "🚪",
                    kind: .room,
                    mascot: MascotRegistry.key(kind: .room, blueprintSlug: room.blueprintSlug),
                    lease: lease,
                    attachments: tiles,
                    blueprintSlug: room.blueprintSlug,
                    state: roomState(room.state, blockedCount: room.blockedCount, humanGate: room.humanGate),
                    health: TwinHealth(blocked: room.blockedCount ?? 0, notes: notes),
                    agent: agent,
                    skills: belt,
                    net: bp?.walls?.network == true ? NetFace(internalOK: true, externalOK: false) : NetFace(internalOK: false, externalOK: false),
                    born: born,
                    tenantID: placement.tenantID,
                    viewpoint: Self.viewpoint(workdir: placement.workdir, here: here)
                )
            }
            let overallState = roomChildren.contains { $0.state == .block || $0.state == .gate }
                ? (roomChildren.contains { $0.state == .gate } ? NodeState.gate : NodeState.block)
                : roomState(placement.state, blockedCount: nil, humanGate: nil)
            let lease = placement.workdir.map { path in
                TwinLease(appName: URL(fileURLWithPath: path).lastPathComponent, detail: path)
            }
            return TwinNode(
                id: placement.id,
                name: placement.title ?? placement.id,
                icon: "📋",
                kind: .placement,
                mascot: MascotRegistry.key(kind: .placement, blueprintSlug: nil),
                lease: lease,
                state: overallState,
                agent: fallbackAgent,
                born: born,
                tenantID: placement.tenantID,
                viewpoint: Self.viewpoint(workdir: placement.workdir, here: here),
                children: roomChildren
            )
        }
        return TwinNode(
            id: "work-rooms",
            name: CLILocalization.string("SnapshotBuilder+WorkRooms.name"),
            icon: "🏗",
            kind: .zone,
            state: .neutral,
            born: 0,
            children: children
        )
    }
}
