import Foundation
import CommandKit
import LocalizationKit

/// TwinSnapshot 조립기. 공급원은 소유 앱 CLI (`OwnerFetching`) 뿐이다.
public struct SnapshotBuilder: Sendable {
    private let fetcher: any OwnerFetching

    public init(fetcher: any OwnerFetching = CLIOwnerBridge()) {
        self.fetcher = fetcher
    }

    /// 테스트·구 호출 호환 — 러너만 갈아끼운 CLI 브리지.
    public init(sources: SnapshotSources = SnapshotSources(), runner: CommandRunning, fm: FileManager = .default) {
        _ = sources
        _ = fm
        self.fetcher = CLIOwnerBridge(runner: runner)
    }

    public func build() async -> TwinSnapshot {
        async let placementsR = fetcher.placements()
        async let blueprintsR = fetcher.blueprints()
        async let seatsR = fetcher.seats()
        async let deckR = fetcher.deck()
        async let shipR = fetcher.shipJobs()
        async let vaultR = fetcher.vault()
        async let hostR = fetcher.hostPulse()
        async let permR = fetcher.permission()
        async let archiveR = fetcher.sessionArchive()
        async let skillsR = fetcher.installedSkills()
        async let usageR = fetcher.skillUsage()
        async let tenantsR = fetcher.tenants()
        async let sessionsR = fetcher.sessions()
        async let hooksR = fetcher.hooks()
        async let reachR = fetcher.reach()

        let placementsB = await placementsR
        let blueprintsB = await blueprintsR
        let seatsB = await seatsR
        let deckB = await deckR
        let shipB = await shipR
        let vaultB = await vaultR
        let hostB = await hostR
        let permB = await permR
        let archiveB = await archiveR
        let skillsB = await skillsR
        let usageB = await usageR
        let tenantsB = await tenantsR
        let sessionsB = await sessionsR
        let hooksB = await hooksR
        let reachB = await reachR

        var notes: [String] = []
        for note in [placementsB.note, blueprintsB.note, seatsB.note, deckB.note, shipB.note, vaultB.note, hostB.note, permB.note, archiveB.note, skillsB.note, tenantsB.note, sessionsB.note, hooksB.note, reachB.note] {
            if let note { notes.append(note) }
        }

        let toolbelts = Dictionary(uniqueKeysWithValues: blueprintsB.value.map { ($0.slug, $0.toolbelt ?? []) })
        let usage = usageB.value
        let usageKnown = usageB.note == nil
        if let note = usageB.note { notes.append(note) }

        let placements = placementsB.value
        let active = placements.filter { Self.isActivePlacement($0) }
        let waiting = placements.filter { Self.isLobbyPlacement($0) }
        let archived = placements.filter { Self.isArchive($0.state) }

        let referenced = Set(toolbelts.values.flatMap { $0 })
        var skillNames = skillsB.value
        if skillNames.isEmpty { skillNames = Array(referenced).sorted() }

        let here = FileManager.default.currentDirectoryPath
        let workRoom = buildWorkRoomsNode(
            placements: active,
            blueprints: blueprintsB.value,
            toolbelts: toolbelts,
            usage: usage,
            sessions: sessionsB.value,
            seats: seatsB.value,
            here: here)
        let lobbyRoom = buildLobbyNode(placements: waiting, here: here)
        let archiveRoom = buildArchiveNode(placements: archived, sessionArchiveCount: archiveB.value, here: here)
        let seatsRoom = buildSeatsNode(seats: seatsB.value, here: here)
        let skillsRoom = buildSkillsNode(
            names: skillNames, usage: usage, referenced: referenced,
            usageKnown: usageKnown, usageNote: usageB.note
        )
        let sessionsRoom = buildSessionsNode(deckState: deckB.value, cards: sessionsB.value, here: here)
        let appsRoom = buildAppsNode(ship: shipB.value)
        let facilitiesRoom = buildFacilitiesNode(
            vault: vaultB.value, permission: permB.value, host: hostB.value, hooks: hooksB.value)

        let telemetry = HostTelemetry(
            load1: hostB.value.load1 ?? shipB.value.load1,
            ncpu: shipB.value.ncpu,
            memUsedGB: nil,
            memTotGB: nil,
            intNetOK: reachB.value.intNetOK,
            extNetOK: nil
        )

        // 테넌트 귀속 키 정본: `placement.tenantID` 가 방(placement)의 테넌트다.
        // `seat.keys.tenant`(= SeatDTO.tenant)는 자리(seat)의 테넌트일 뿐, 방 귀속을 재정의하지 않는다.
        // isolation-manager 목록에 없는 id(예 tenant:silneobal)도 실측 placement/seat 에서 나오면
        // 합집합에 넣는다 — 원장이 이미 아는 테넌트만 인정하지 않는다.
        var tenantRefs = tenantsB.value.listed
        var seen = Set(tenantRefs.map(\.id))
        let extraIDs = Set(placements.map { $0.tenantID }.compactMap { $0 })
            .union(seatsB.value.compactMap(\.tenant))
        for id in extraIDs.sorted() where !seen.contains(id) {
            tenantRefs.append(TenantRef(id: id, displayName: id, current: id == tenantsB.value.currentID))
            seen.insert(id)
        }
        if let current = tenantsB.value.currentID {
            for i in tenantRefs.indices { tenantRefs[i].current = tenantRefs[i].id == current }
        }

        let rootChildren: [TwinNode]
        if tenantRefs.isEmpty {
            rootChildren = [lobbyRoom, workRoom, seatsRoom, appsRoom, skillsRoom, sessionsRoom, archiveRoom, facilitiesRoom]
        } else {
            let buildings = tenantRefs.map { tenant in
                TwinNode(
                    id: "tenant-\(tenant.id)",
                    name: tenant.displayName,
                    icon: "🏢",
                    kind: .zone,
                    mascot: "command",
                    state: .neutral,
                    born: 0,
                    tenantID: tenant.id,
                    children: [
                        filterZone(workRoom, tenant: tenant.id),
                        filterZone(lobbyRoom, tenant: tenant.id),
                        occupiedSeatsZone(filterZone(seatsRoom, tenant: tenant.id)),
                        warehouseDoor(skillsRoom, tenant: tenant.id),
                        filterZone(archiveRoom, tenant: tenant.id),
                    ]
                )
            }
            let commons = TwinNode(
                id: "fleet-commons",
                name: CLILocalization.string("SnapshotBuilder.name"),
                icon: "🌐",
                kind: .zone,
                state: .neutral,
                born: 0,
                viewpoint: "third",
                children: [appsRoom, skillsRoom, sessionsRoom, facilitiesRoom]
            )
            rootChildren = buildings + [commons]
        }

        let root = TwinNode(
            id: "fleet-root",
            name: CLILocalization.string("SnapshotBuilder.name-2"),
            icon: "🗼",
            kind: .host,
            state: notes.isEmpty ? .neutral : .block,
            health: TwinHealth(
                blocked: notes.count,
                notes: notes + hostNotes(hostB.value)
            ),
            born: 0,
            children: rootChildren
        )

        let flows = buildFlows(active: active, archived: archived, waiting: waiting, skills: skillsRoom)
        var trace = TraceCollector.events(
            placements: placements,
            skillNames: skillNames,
            usage: usage,
            toolbelts: toolbelts,
            usageKnown: usageKnown,
            store: TraceStore()
        )
        if let stamp = hooksB.value.latestCancelAt,
           let date = ISO8601DateFormatter().date(from: stamp) {
            trace.append(TraceEvent(
                t: date.timeIntervalSince1970,
                lane: 0,
                label: hooksB.value.latestCancel ?? "hook cancel",
                state: .block,
                detail: stamp,
                roomID: "facility-hooks"
            ))
            trace.sort { $0.t < $1.t }
        }

        return TwinSnapshot(
            root: root,
            flows: flows,
            telemetry: telemetry,
            trace: trace,
            generatedAt: Date(),
            tenants: tenantRefs,
            currentTenantID: tenantsB.value.currentID
        )
    }


    static func existingTranscriptPath(jsonPath: String?, tool: String?, sessionId: String?) -> String? {
        let fm = FileManager.default
        if let jsonPath, fm.fileExists(atPath: jsonPath) { return jsonPath }
        guard let tool, let sessionId, !sessionId.isEmpty else { return nil }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates: [String]
        switch tool {
        case "grok":
            candidates = ["\(home)/.grok/sessions/\(sessionId)"]
        case "codex":
            candidates = [
                "\(home)/.codex/sessions/\(sessionId).jsonl",
                "\(home)/.codex/sessions/\(sessionId)"
            ]
        default:
            candidates = []
        }
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    static func viewpoint(workdir: String?, here: String) -> String {
        guard let workdir, !workdir.isEmpty else { return "third" }
        if here.hasPrefix(workdir) || workdir.hasPrefix(here) { return "first" }
        return "third"
    }

    private static let activeStates: Set<String> = ["occupied", "executing", "active"]

    static func isActivePlacement(_ placement: PlacementDTO) -> Bool {
        if isActive(placement.state) { return true }
        if let rooms = placement.rooms, rooms.contains(where: {
            guard let s = $0.state else { return false }
            return activeStates.contains(s)
        }) {
            return true
        }
        return false
    }

    static func isLobbyPlacement(_ placement: PlacementDTO) -> Bool {
        guard !isActivePlacement(placement) else { return false }
        return isLobby(placement.state)
    }

    static func isActive(_ state: String?) -> Bool {
        switch state {
        case "executing", "active", "approved": return true
        default: return false
        }
    }

    static func isLobby(_ state: String?) -> Bool {
        switch state {
        case "submitted", "draft", "queued", "pending", "waiting", "planned": return true
        default: return false
        }
    }

    static func isArchive(_ state: String?) -> Bool {
        switch state {
        case "completed", "dismantled", "rejected", "abandoned", "failed": return true
        default: return false
        }
    }

    func hostNotes(_ pulse: HostPulse) -> [String] {
        var notes: [String] = []
        if let hang = pulse.hang, hang > 0 { notes.append("host hang \(hang)") }
        if let mem = pulse.memUsedPct { notes.append(String(format: "mem %.0f%%", mem)) }
        if let disk = pulse.diskUsedPct { notes.append(String(format: "disk %.0f%%", disk)) }
        return notes
    }

    func roomState(_ raw: String?, blockedCount: Int?, humanGate: Bool?) -> NodeState {
        if humanGate == true { return .gate }
        if let blockedCount, blockedCount > 0 { return .block }
        switch raw {
        case "completed", "dismantled": return .done
        case "executing", "active", "occupied": return .exec
        case "queued", "pending", "waiting", "planned": return .queue
        case "sleeping": return .sleep
        default: return .neutral
        }
    }

    func skillTile(_ name: String, usage: [String: SkillUsage]) -> TwinAttachment {
        let hit = usage[name]
        return TwinAttachment(
            kind: "skill", name: name,
            callCount: hit?.callCount,
            lastCalledAt: hit?.lastCalledAt,
            tools: hit?.tools
        )
    }

    func bornSeconds(_ raw: Double?) -> Double {
        guard let raw, raw > 0 else { return 0 }
        if raw > 10_000_000_000 { return raw / 1000 }
        return raw
    }
}

/// 구 테스트가 참조하던 경로 묶음 — CLI 브리지로 옮긴 뒤에도 타입만 남긴다.
public struct SnapshotSources: Sendable {
    public var homeDir: URL
    public init(homeDir: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDir = homeDir
    }
}
