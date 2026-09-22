import Foundation
import CommandKit
import InteropKit

/// PATH 소유 CLI. 테스트는 `OwnerFetching` 목을 넣는다.
public struct CLIOwnerBridge: OwnerFetching {
    private let runner: CommandRunning
    public var isolation = HostPlatform.cliBinPath("agent-tenant-isolation-manager")
    public var workTodo = HostPlatform.cliBinPath("agent-work-todo")
    public var seats = HostPlatform.cliBinPath("agent-seat-manager")
    public var deck = HostPlatform.cliBinPath("agent-deck")
    public var adm = HostPlatform.cliBinPath("app-build-manager")
    public var vault = HostPlatform.cliBinPath("agent-vault")
    public var permission = HostPlatform.cliBinPath("mac-permission-monitor")
    public var workMonitor = HostPlatform.cliBinPath("agent-work-monitor")
    public var sessionArchive = HostPlatform.cliBinPath("agent-session-archive")
    public var handoff = HostPlatform.cliBinPath("agent-handoff")
    public var ledger = HostPlatform.cliBinPath("agent-session-context-ledger")
    public var hooksCLI = HostPlatform.cliBinPath("agent-hooks-status")
    public var reachCLI = HostPlatform.cliBinPath("agent-reach-watch")

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func placements() async -> BridgeResult<[PlacementDTO]> {
        await decodeList(workTodo, ["placement", "list", "--all", "--json"], as: PlacementDTO.self, timeout: 8)
    }

    public func blueprints() async -> BridgeResult<[BlueprintDTO]> {
        await decodeList(workTodo, ["room", "list", "--json"], as: BlueprintDTO.self, timeout: 8)
    }

    public func seats() async -> BridgeResult<[SeatDTO]> {
        await decodeList(seats, ["seats", "--json"], as: SeatDTO.self, timeout: 6)
    }

    public func deck() async -> BridgeResult<AgentDeckStateDTO?> {
        let raw = await run(deck, ["status", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail): return BridgeResult(value: nil, note: fail.message)
        case .success(let data):
            do {
                let state = try JSONDecoder().decode(AgentDeckStateDTO.self, from: CLIJSON.payload(data))
                return BridgeResult(value: state)
            } catch {
                if let snippet = CLIJSON.string(data, keyPath: ["snippet"]),
                   let snippetData = snippet.data(using: String.Encoding.utf8) {
                    do {
                        let file = try JSONDecoder().decode(DeckSnippet.self, from: snippetData)
                        return BridgeResult(value: file.state)
                    } catch {
                        return BridgeResult(value: nil, note: "agent-deck snippet 파싱 실패: \(error)")
                    }
                }
                return BridgeResult(value: nil, note: "agent-deck status 에 state 없음: \(error)")
            }
        }
    }

    public func shipJobs() async -> BridgeResult<ShipBridge> {
        let raw = await run(adm, ["ship-queue", "list", "--json"], timeout: 10)
        switch raw {
        case .failure(let fail): return BridgeResult(value: ShipBridge(), note: fail.message)
        case .success(let data):
            struct Gate: Codable { var load1: Double?; var ncpu: Int? }
            struct Envelope: Codable {
                var jobs: [ShipJobDTO]?
                var compileGate: Gate?
            }
            do {
                let env = try JSONDecoder().decode(Envelope.self, from: CLIJSON.payload(data))
                return BridgeResult(value: ShipBridge(jobs: env.jobs ?? [], load1: env.compileGate?.load1, ncpu: env.compileGate?.ncpu))
            } catch {
                return BridgeResult(value: ShipBridge(), note: "ship-queue list 파싱 실패: \(error)")
            }
        }
    }

    public func vault() async -> BridgeResult<VaultBridge> {
        let raw = await run(vault, ["status", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail): return BridgeResult(value: VaultBridge(cards: 0, grants: 0, infisical: 0), note: fail.message)
        case .success(let data):
            struct Env: Codable {
                var credentialCards: Int?
                var grants: Int?
                var infisicalConnections: Int?
                var activeTenantID: String?
            }
            let env: Env
            var note: String?
            do {
                env = try JSONDecoder().decode(Env.self, from: CLIJSON.payload(data))
            } catch {
                env = Env()
                note = "agent-vault status 파싱 실패: \(error)"
            }
            return BridgeResult(value: VaultBridge(
                cards: env.credentialCards ?? 0,
                grants: env.grants ?? 0,
                infisical: env.infisicalConnections ?? 0,
                tenant: env.activeTenantID
            ), note: note)
        }
    }

    public func hostPulse() async -> BridgeResult<HostPulse> {
        let raw = await run(workMonitor, ["host", "--json"], timeout: 8)
        switch raw {
        case .failure(let fail): return BridgeResult(value: HostPulse(), note: fail.message)
        case .success(let data):
            struct Env: Codable {
                var load1: Double?
                var mem_used_pct: Double?
                var disk_used_pct: Double?
                var hang: Int?
                var live: Int?
            }
            let env: Env
            var note: String?
            do {
                env = try JSONDecoder().decode(Env.self, from: CLIJSON.payload(data))
            } catch {
                env = Env()
                note = "agent-work-monitor host 파싱 실패: \(error)"
            }
            return BridgeResult(value: HostPulse(
                load1: env.load1,
                memUsedPct: env.mem_used_pct,
                diskUsedPct: env.disk_used_pct,
                hang: env.hang,
                live: env.live
            ), note: note)
        }
    }

    public func permission() async -> BridgeResult<PermissionBridge> {
        let raw = await run(permission, ["status", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail): return BridgeResult(value: PermissionBridge(summary: "조회 실패"), note: fail.message)
        case .success(let data):
            let published = CLIJSON.bool(data, key: "published") ?? false
            let mtime = CLIJSON.string(data, keyPath: ["mtime"]) ?? ""
            let summary = published ? "state 미러 \(mtime)" : "미러 없음 — TCC 단정하지 않음"
            return BridgeResult(value: PermissionBridge(summary: summary))
        }
    }

    public func sessionArchive() async -> BridgeResult<Int> {
        let raw = await run(sessionArchive, ["status", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail): return BridgeResult(value: 0, note: fail.message)
        case .success(let data):
            struct Env: Codable { var archivedCount: Int? }
            do {
                let env = try JSONDecoder().decode(Env.self, from: CLIJSON.payload(data))
                return BridgeResult(value: env.archivedCount ?? 0)
            } catch {
                return BridgeResult(value: 0, note: "agent-session-archive 파싱 실패: \(error)")
            }
        }
    }

    public func installedSkills() async -> BridgeResult<[String]> {
        let raw = await run(handoff, ["skill", "list", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail): return BridgeResult(value: [], note: fail.message)
        case .success(let data):
            struct Item: Codable { var id: String?; var name: String? }
            do {
                let items = try JSONDecoder().decode([Item].self, from: CLIJSON.payload(data))
                return BridgeResult(value: items.map { $0.id ?? $0.name ?? "" }.filter { !$0.isEmpty })
            } catch {
                do {
                    let names = try JSONDecoder().decode([String].self, from: CLIJSON.payload(data))
                    return BridgeResult(value: names)
                } catch {
                    return BridgeResult(value: [], note: "agent-handoff skill list 형식 미확인: \(error)")
                }
            }
        }
    }

    public func tenants() async -> BridgeResult<TenantBridge> {
        async let listedRaw = run(isolation, ["list", "--json"], timeout: 6)
        async let currentRaw = run(isolation, ["context", "current", "--json"], timeout: 4)
        let listed = await listedRaw
        let current = await currentRaw
        var currentID: String?
        if case .success(let data) = current {
            struct Ctx: Codable { var tenantID: String? }
            do {
                currentID = try JSONDecoder().decode(Ctx.self, from: CLIJSON.payload(data)).tenantID
            } catch {
                currentID = nil
            }
        }
        var refs: [TenantRef] = []
        switch listed {
        case .failure(let fail):
            return BridgeResult(value: TenantBridge(currentID: currentID, listed: []), note: fail.message)
        case .success(let data):
            struct Item: Codable {
                var id: String?
                var displayName: String?
                var slug: String?
            }
            let items: [Item]
            var note: String?
            do {
                items = try JSONDecoder().decode([Item].self, from: CLIJSON.payload(data))
            } catch {
                items = []
                note = "isolation list 파싱 실패: \(error)"
            }
            refs = items.compactMap { item in
                guard let id = item.id else { return nil }
                return TenantRef(id: id, displayName: item.displayName ?? item.slug ?? id, current: id == currentID)
            }
            return BridgeResult(value: TenantBridge(currentID: currentID, listed: refs), note: note)
        }
    }

    public func hooks() async -> BridgeResult<HooksBridge> {
        let raw = await run(hooksCLI, ["status", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail):
            return BridgeResult(value: HooksBridge(), note: fail.message)
        case .success(let data):
            struct Env: Decodable {
                var overallOK: Bool?
                var overallLabel: String?
                var layers: [HookLayerDTO]?
                var fleet: Fleet?
                var cancels: Cancels?
                struct Fleet: Decodable { var liveGrok: Int? }
                struct Cancels: Decodable {
                    var recent: [Hit]?
                    struct Hit: Decodable {
                        var timestamp: String?
                        var message: String?
                        var trigger: String?
                        var sessionID: String?
                    }
                }
            }
            do {
                let env = try JSONDecoder().decode(Env.self, from: CLIJSON.payload(data))
                let hit = env.cancels?.recent?.first
                let cancel = [hit?.trigger, hit?.message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return BridgeResult(value: HooksBridge(
                    ok: env.overallOK ?? false,
                    label: env.overallLabel ?? "",
                    layers: env.layers ?? [],
                    liveGrok: env.fleet?.liveGrok,
                    latestCancel: cancel.isEmpty ? nil : cancel,
                    latestCancelAt: hit?.timestamp
                ))
            } catch {
                return BridgeResult(value: HooksBridge(), note: "agent-hooks-status status 파싱 실패: \(error)")
            }
        }
    }

    public func reach() async -> BridgeResult<ReachBridge> {
        let raw = await run(reachCLI, ["status", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail):
            return BridgeResult(value: ReachBridge(), note: fail.message)
        case .success(let data):
            struct Scan: Decodable {
                var reached: Int?
                var unreached: Int?
                var averageScore: Double?
            }
            struct Env: Decodable {
                var hasScan: Bool?
                var lastScan: Scan?
            }
            do {
                let env = try JSONDecoder().decode(Env.self, from: CLIJSON.payload(data))
                return BridgeResult(value: ReachBridge(
                    hasScan: env.hasScan ?? (env.lastScan != nil),
                    reached: env.lastScan?.reached,
                    unreached: env.lastScan?.unreached,
                    averageScore: env.lastScan?.averageScore
                ))
            } catch {
                return BridgeResult(value: ReachBridge(), note: "agent-reach-watch status 파싱 실패: \(error)")
            }
        }
    }

    public func sessions() async -> BridgeResult<[SessionCardDTO]> {
        await decodeList(
            ledger, ["sessions", "--since", "7d", "--limit", "20", "--json"],
            as: SessionCardDTO.self, timeout: 8)
    }

    public func skillUsage() async -> BridgeResult<[String: SkillUsage]> {
        let raw = await run(ledger, ["skills", "--since", "7d", "--limit", "80", "--json"], timeout: 6)
        switch raw {
        case .failure(let fail): return BridgeResult(value: [:], note: fail.message)
        case .success(let data):
            struct Item: Codable {
                var name: String?
                var skill: String?
                var sessions: Int?
                var callCount: Int?
                var lastSeen: Double?
                var tools: [String]?
            }
            let apple: Double = 978_307_200
            var usage: [String: SkillUsage] = [:]
            do {
                let items = try JSONDecoder().decode([Item].self, from: CLIJSON.payload(data))
                for item in items {
                    let name = item.name ?? item.skill ?? ""
                    guard !name.isEmpty else { continue }
                    let count = item.callCount ?? item.sessions ?? 0
                    var last: Double? = nil
                    if let seen = item.lastSeen {
                        if seen > 10_000_000_000 { last = seen / 1000 }
                        else if seen < 2_000_000_000 { last = seen + apple }
                        else { last = seen }
                    }
                    usage[name] = SkillUsage(callCount: count, lastCalledAt: last, tools: item.tools ?? [])
                }
                return BridgeResult(value: usage)
            } catch {
                return BridgeResult(value: [:], note: "agent-session-context-ledger skills 파싱 실패: \(error)")
            }
        }
    }

    // MARK: - 실행

    private func decodeList<T: Decodable>(_ bin: String, _ args: [String], as: T.Type, timeout: TimeInterval) async -> BridgeResult<[T]> {
        let raw = await run(bin, args, timeout: timeout)
        switch raw {
        case .failure(let fail): return BridgeResult(value: [], note: fail.message)
        case .success(let data):
            do {
                let list = try JSONDecoder().decode([T].self, from: CLIJSON.payload(data))
                return BridgeResult(value: list)
            } catch {
                return BridgeResult(value: [], note: "\(bin) \(args.joined(separator: " ")) 목록 파싱 실패: \(error)")
            }
        }
    }

    private func run(_ bin: String, _ args: [String], timeout: TimeInterval) async -> Result<Data, BridgeFail> {
        let result = await runner.run(bin, args, timeout: timeout)
        guard result.ok, let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = URL(fileURLWithPath: bin).lastPathComponent
            return .failure(BridgeFail("\(name) \(args.first ?? "") 실패\(err.isEmpty ? "" : ": \(err)")"))
        }
        return .success(data)
    }
}

struct BridgeFail: Error {
    var message: String
    init(_ message: String) { self.message = message }
}

private struct DeckSnippet: Codable {
    var state: AgentDeckStateDTO?
}

public enum CLIJSON {
    /// 스트림 앞뒤의 경고 배너나 ANSI/공백을 건너뛰고 순수 JSON 본문 슬라이스
    public static func cleanJSONData(_ data: Data) -> Data {
        guard let str = String(data: data, encoding: .utf8) else { return data }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") && !trimmed.hasPrefix("[") else { return data }
        return extractJSONSlice(from: str) ?? data
    }

    private static func extractJSONSlice(from str: String) -> Data? {
        let braceSlice = sliceBoundary(str, open: "{", close: "}")
        let bracketSlice = sliceBoundary(str, open: "[", close: "]")
        return braceSlice ?? bracketSlice
    }

    private static func sliceBoundary(_ str: String, open: Character, close: Character) -> Data? {
        guard let first = str.firstIndex(of: open), let last = str.lastIndex(of: close), first < last else {
            return nil
        }
        return Data(str[first...last].utf8)
    }

    /// `{payload}` (work-todo v2) 또는 `{result}` (interop) 또는 본문.
    public static func payload(_ data: Data) -> Data {
        let clean = cleanJSONData(data)
        do {
            guard let obj = try JSONSerialization.jsonObject(with: clean) as? [String: Any] else { return clean }
            if let payload = obj["payload"] {
                do {
                    return try JSONSerialization.data(withJSONObject: payload)
                } catch {
                    return clean
                }
            }
            if let result = obj["result"] {
                do {
                    return try JSONSerialization.data(withJSONObject: result)
                } catch {
                    return clean
                }
            }
            return clean
        } catch {
            return clean
        }
    }

    static func string(_ data: Data, keyPath: [String]) -> String? {
        let clean = cleanJSONData(data)
        do {
            var obj: Any = try JSONSerialization.jsonObject(with: clean)
            for key in keyPath {
                guard let dict = obj as? [String: Any], let next = dict[key] else { return nil }
                obj = next
            }
            return obj as? String
        } catch {
            return nil
        }
    }

    static func bool(_ data: Data, key: String) -> Bool? {
        let clean = cleanJSONData(data)
        do {
            guard let dict = try JSONSerialization.jsonObject(with: clean) as? [String: Any] else { return nil }
            return dict[key] as? Bool
        } catch {
            return nil
        }
    }
}
