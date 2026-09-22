import Foundation
import LocalizationKit

/// 자리·스킬·세션·로비·아카이브·시설
extension SnapshotBuilder {
    func queueItemState(_ raw: String?) -> NodeState {
        switch raw {
        case "queued", "pending": return .queue
        case "running", "building": return .exec
        case "failed": return .block
        case "succeeded", "done", "shipped": return .done
        default: return .neutral
        }
    }

    func buildAppsNode(ship: ShipBridge) -> TwinNode {
        let iso = ISO8601DateFormatter()
        let items = ship.jobs.map { job -> TwinNode in
            let born = job.enqueuedAt.flatMap { iso.date(from: $0)?.timeIntervalSince1970 } ?? 0
            return TwinNode(
                id: "shipjob-\(job.id ?? job.displayName)",
                name: job.displayName,
                icon: "📦",
                kind: .queueItem,
                mascot: MascotRegistry.key(kind: .queueItem, blueprintSlug: nil),
                state: queueItemState(job.jobStatus),
                health: TwinHealth(notes: job.detail.map { [$0] } ?? []),
                born: born
            )
        }
        let adm = TwinNode(
            id: "app-build-manager",
            name: CLILocalization.format("SnapshotBuilder+Zones.name", items.count),
            icon: "🏭",
            kind: .app,
            mascot: MascotRegistry.key(kind: .app, blueprintSlug: nil),
            state: items.contains { $0.state == .exec } ? .exec : (items.contains { $0.state == .queue } ? .queue : .neutral),
            born: 0,
            viewpoint: "third",
            children: items
        )
        return TwinNode(id: "apps", name: CLILocalization.string("SnapshotBuilder+Zones.name-2"), icon: "🏢", kind: .zone, state: .neutral, born: 0, viewpoint: "third", children: [adm])
    }

    func buildSeatsNode(seats: [SeatDTO], here: String) -> TwinNode {
        let children = seats.map { seat -> TwinNode in
            let vacant = seat.kind == "vacant" || (seat.occupant ?? "").isEmpty
            let agent: TwinAgent? = vacant ? nil : TwinAgent(
                actor: seat.occupant ?? seat.handle,
                tool: seat.kind == "app" ? "app" : seat.occupant,
                model: seat.model,
                env: seat.workdir
            )
            var equipment: [TwinAttachment] = []
            if let model = seat.model {
                equipment.append(TwinAttachment(kind: "equipment", name: "model", value: model))
            }
            if let tier = seat.tier {
                equipment.append(TwinAttachment(kind: "equipment", name: "tier", value: tier))
            }
            let lease = seat.workdir.map { TwinLease(appName: URL(fileURLWithPath: $0).lastPathComponent, detail: $0) }
            return TwinNode(
                id: "seat-\(seat.handle)",
                name: seat.handle,
                icon: "🪑",
                kind: .seat,
                mascot: MascotRegistry.key(kind: .seat, blueprintSlug: nil),
                lease: lease,
                attachments: equipment,
                state: vacant ? .sleep : .exec,
                agent: agent,
                born: 0,
                tenantID: seat.tenant,
                viewpoint: Self.viewpoint(workdir: seat.workdir, here: here)
            )
        }
        return TwinNode(id: "seats", name: CLILocalization.string("SnapshotBuilder+Zones.name-3"), icon: "💺", kind: .zone, state: .neutral, born: 0, children: children)
    }

    func buildSkillsNode(
        names: [String],
        usage: [String: SkillUsage],
        referenced: Set<String>,
        usageKnown: Bool,
        usageNote: String?
    ) -> TwinNode {
        func skillNode(_ name: String) -> TwinNode {
            let hit = usage[name]
            let called = usageKnown && (hit?.callCount ?? 0) > 0
            var notes: [String] = []
            if usageKnown, !called { notes.append("호출 원장에 없음") }
            if !referenced.contains(name) { notes.append("방 toolbelt 미참조") }
            let state: NodeState
            if called { state = .exec }
            else if !referenced.contains(name) { state = .sleep }
            else { state = .neutral }
            return TwinNode(
                id: "skill-\(name)",
                name: name,
                icon: "📦",
                kind: .skill,
                mascot: called ? "skill-ok" : "skill-web",
                attachments: [skillTile(name, usage: usage)],
                state: state,
                health: TwinHealth(notes: notes),
                born: 0
            )
        }
        let unique = Array(Set(names)).sorted()
        let referencedNodes = unique.filter { referenced.contains($0) }.map(skillNode)
        let unreferencedNodes = unique.filter { !referenced.contains($0) }.map(skillNode)
        let uncalledNodes = usageKnown ? unique.filter { (usage[$0]?.callCount ?? 0) == 0 }.map(skillNode) : []
        let bins = [
            TwinNode(
                id: "skill-referenced", name: CLILocalization.format("SnapshotBuilder+Zones.name-4", referencedNodes.count), icon: "📎",
                kind: .warehouse, mascot: "skills",
                state: referencedNodes.isEmpty ? .neutral : .exec, born: 0, children: referencedNodes
            ),
            TwinNode(
                id: "skill-unreferenced", name: CLILocalization.format("SnapshotBuilder+Zones.name-5", unreferencedNodes.count), icon: "🕸",
                kind: .warehouse, mascot: "skills",
                state: unreferencedNodes.isEmpty ? .neutral : .sleep, born: 0, children: unreferencedNodes
            ),
            TwinNode(
                id: "skill-uncalled",
                name: usageKnown ? "미호출 (\(uncalledNodes.count))" : "미호출 (원장 없음)",
                icon: "👻",
                kind: .warehouse, mascot: "skills",
                state: usageKnown ? (uncalledNodes.isEmpty ? .neutral : .queue) : .gate,
                health: TwinHealth(notes: usageKnown ? [] : [usageNote ?? "skills CLI 실패 — 미호출을 세지 않음"]),
                born: 0, children: uncalledNodes
            ),
        ]
        return TwinNode(
            id: "skill-warehouse",
            name: CLILocalization.format("SnapshotBuilder+Zones.name-6", unique.count),
            icon: "🏬",
            kind: .warehouse,
            mascot: MascotRegistry.key(kind: .warehouse, blueprintSlug: nil),
            state: .neutral,
            born: 0,
            viewpoint: "third",
            children: bins
        )
    }

    func buildSessionsNode(
        deckState: AgentDeckStateDTO?,
        cards: [SessionCardDTO],
        here: String
    ) -> TwinNode {
        let pageSize = 20
        let page = Array(cards.prefix(pageSize))
        var notes: [String] = []
        if let deckState {
            notes.append("agents \(deckState.agents ?? 0)")
            notes.append("working \(deckState.agentsWorking ?? 0)")
            notes.append("archivedSessions \(deckState.archivedSessions ?? 0)")
        } else {
            notes.append("agent-deck status 없음")
        }
        if cards.count > pageSize {
            notes.append("최근 \(pageSize)장만 그림 · 원장 \(cards.count)건")
        }
        if page.isEmpty {
            notes.append("세션 카드 없음 — 지어내지 않음")
        }
        let children = page.map { card -> TwinNode in
            let lease = card.cwd.map { TwinLease(appName: URL(fileURLWithPath: $0).lastPathComponent, detail: $0) }
            let agent = TwinAgent(
                actor: card.tool.map { "agent:\($0)@host" } ?? "session",
                sessionID: card.sessionId,
                tool: card.tool,
                env: card.cwd
            )
            var attachments: [TwinAttachment] = []
            if let source = Self.existingTranscriptPath(jsonPath: card.path, tool: card.tool, sessionId: card.sessionId) {
                attachments.append(TwinAttachment(kind: "transcript", name: "source", value: source))
            }
            return TwinNode(
                id: "session-\(card.sessionId ?? card.cardName)",
                name: card.cardName,
                icon: "💬",
                kind: .room,
                lease: lease,
                attachments: attachments,
                state: .exec,
                health: TwinHealth(notes: card.messageCount.map { ["messages \($0)"] } ?? []),
                agent: agent,
                tokens: card.inputTokens,
                maxTokens: card.contextWindow,
                born: card.lastActive ?? 0,
                viewpoint: Self.viewpoint(workdir: card.cwd, here: here)
            )
        }
        return TwinNode(
            id: "sessions",
            name: page.isEmpty ? "세션 (카드 없음)" : "세션 (\(page.count))",
            icon: "🖥",
            kind: .zone,
            state: children.isEmpty ? .sleep : .exec,
            health: TwinHealth(notes: notes),
            born: 0,
            viewpoint: "third",
            children: children
        )
    }

    func buildLobbyNode(placements: [PlacementDTO], here: String) -> TwinNode {
        let children = placements.map { placement -> TwinNode in
            let roomChildren = (placement.rooms ?? []).map { room -> TwinNode in
                TwinNode(
                    id: room.id,
                    name: room.blueprintSlug ?? room.id,
                    icon: "🚪",
                    kind: .room,
                    mascot: MascotRegistry.key(kind: .room, blueprintSlug: room.blueprintSlug),
                    blueprintSlug: room.blueprintSlug,
                    state: roomState(room.state, blockedCount: room.blockedCount, humanGate: room.humanGate),
                    born: bornSeconds(placement.createdAt ?? placement.updatedAt),
                    tenantID: placement.tenantID,
                    viewpoint: Self.viewpoint(workdir: placement.workdir, here: here)
                )
            }
            return TwinNode(
                id: "lobby-\(placement.id)",
                name: placement.title ?? placement.id,
                icon: "📨",
                kind: .placement,
                mascot: "mail",
                state: .queue,
                born: bornSeconds(placement.createdAt ?? placement.updatedAt),
                tenantID: placement.tenantID,
                viewpoint: Self.viewpoint(workdir: placement.workdir, here: here),
                children: roomChildren
            )
        }
        return TwinNode(
            id: "lobby",
            name: CLILocalization.format("SnapshotBuilder+Zones.name-7", children.count),
            icon: "🏛",
            kind: .zone,
            mascot: "command",
            state: children.isEmpty ? .neutral : .queue,
            born: 0,
            children: children
        )
    }

    func buildArchiveNode(placements: [PlacementDTO], sessionArchiveCount: Int, here: String) -> TwinNode {
        var children = placements.map { placement -> TwinNode in
            let roomChildren = (placement.rooms ?? []).map { room -> TwinNode in
                TwinNode(
                    id: room.id,
                    name: room.blueprintSlug ?? room.id,
                    icon: "🚪",
                    kind: .room,
                    mascot: MascotRegistry.key(kind: .room, blueprintSlug: room.blueprintSlug),
                    blueprintSlug: room.blueprintSlug,
                    state: roomState(room.state, blockedCount: room.blockedCount, humanGate: room.humanGate),
                    born: bornSeconds(placement.createdAt ?? placement.updatedAt),
                    tenantID: placement.tenantID,
                    viewpoint: Self.viewpoint(workdir: placement.workdir, here: here)
                )
            }
            return TwinNode(
                id: placement.id,
                name: placement.title ?? placement.id,
                icon: placement.state == "rejected" ? "🗑" : "📁",
                kind: .placement,
                mascot: "drawer",
                state: placement.state == "rejected" ? .block : .done,
                born: bornSeconds(placement.createdAt ?? placement.updatedAt),
                tenantID: placement.tenantID,
                viewpoint: Self.viewpoint(workdir: placement.workdir, here: here),
                children: roomChildren
            )
        }
        if sessionArchiveCount > 0 {
            children.append(TwinNode(
                id: "session-archive",
                name: "agent-session-archive (\(sessionArchiveCount))",
                icon: "🗄",
                kind: .app,
                state: .done,
                born: 0,
                viewpoint: "third"
            ))
        }
        return TwinNode(
            id: "archive",
            name: CLILocalization.format("SnapshotBuilder+Zones.name-8", children.count),
            icon: "🗄",
            kind: .zone,
            mascot: "drawer",
            state: .done,
            born: 0,
            children: children
        )
    }

    func buildFacilitiesNode(
        vault: VaultBridge, permission: PermissionBridge, host: HostPulse, hooks: HooksBridge
    ) -> TwinNode {
        let vaultNode = TwinNode(
            id: "facility-vault",
            name: "agent-vault",
            icon: "🏦",
            kind: .app,
            mascot: "facility",
            state: vault.cards > 0 ? .neutral : .sleep,
            health: TwinHealth(notes: [
                "cards \(vault.cards)",
                "grants \(vault.grants)",
                "infisical \(vault.infisical)",
                vault.tenant.map { "tenant \($0)" } ?? "tenant 없음"
            ]),
            born: 0
        )
        let permNode = TwinNode(
            id: "facility-tcc",
            name: "mac-permission-monitor",
            icon: "🔐",
            kind: .app,
            mascot: "facility",
            state: .sleep,
            health: TwinHealth(notes: [permission.summary]),
            born: 0
        )
        let hostNode = TwinNode(
            id: "facility-host",
            name: "agent-work-monitor host",
            icon: "🩺",
            kind: .app,
            mascot: "facility",
            state: (host.hang ?? 0) > 0 ? .block : .neutral,
            health: TwinHealth(notes: hostNotes(host)),
            born: 0
        )
        let hookChildren = hooks.layers.map { layer -> TwinNode in
            TwinNode(
                id: "hook-\(layer.displayName)",
                name: layer.displayName.isEmpty ? "layer" : layer.displayName,
                icon: "🪝",
                kind: .queueItem,
                state: (layer.hookCount ?? 0) == 0 ? .sleep : .exec,
                health: TwinHealth(notes: [
                    "hooks \(layer.hookCount ?? 0)",
                    (layer.isUserImmutable == true) ? "uchg" : "writable",
                    layer.path ?? ""
                ].filter { !$0.isEmpty }),
                born: 0
            )
        }
        var hookNotes: [String] = [hooks.label].filter { !$0.isEmpty }
        if let live = hooks.liveGrok { hookNotes.append("live_grok \(live)") }
        if let cancel = hooks.latestCancel { hookNotes.append(cancel) }
        let hooksNode = TwinNode(
            id: "facility-hooks",
            name: "agent-hooks-status",
            icon: "🪝",
            kind: .app,
            mascot: "facility",
            state: hooks.ok ? (hookChildren.contains { $0.state == .exec } ? .exec : .neutral) : .block,
            health: TwinHealth(notes: hookNotes),
            born: 0,
            children: hookChildren
        )
        return TwinNode(
            id: "host-facilities",
            name: CLILocalization.string("SnapshotBuilder+Zones.name-9"),
            icon: "🏭",
            kind: .zone,
            mascot: "facility",
            state: (host.hang ?? 0) > 0 || !hooks.ok ? .block : .neutral,
            born: 0,
            viewpoint: "third",
            children: [vaultNode, permNode, hostNode, hooksNode]
        )
    }
}
