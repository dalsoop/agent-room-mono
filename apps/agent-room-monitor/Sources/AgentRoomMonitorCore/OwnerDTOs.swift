import Foundation
import CommandKit
import InteropKit

/// 소유 앱 CLI 한 번의 결과. 실패해도 스냅샷 전체가 죽지 않는다.
public struct BridgeResult<T: Sendable>: Sendable {
    public var value: T
    public var note: String?
    public init(value: T, note: String? = nil) {
        self.value = value
        self.note = note
    }
}

/// Room Monitor 가 디스크를 훑지 않고 묻는 면. 구현은 소유 앱 CLI 뿐이다.
public protocol OwnerFetching: Sendable {
    func placements() async -> BridgeResult<[PlacementDTO]>
    func blueprints() async -> BridgeResult<[BlueprintDTO]>
    func seats() async -> BridgeResult<[SeatDTO]>
    func deck() async -> BridgeResult<AgentDeckStateDTO?>
    func shipJobs() async -> BridgeResult<ShipBridge>
    func vault() async -> BridgeResult<VaultBridge>
    func hostPulse() async -> BridgeResult<HostPulse>
    func permission() async -> BridgeResult<PermissionBridge>
    func sessionArchive() async -> BridgeResult<Int>
    func installedSkills() async -> BridgeResult<[String]>
    func skillUsage() async -> BridgeResult<[String: SkillUsage]>
    func tenants() async -> BridgeResult<TenantBridge>
    func sessions() async -> BridgeResult<[SessionCardDTO]>
    func hooks() async -> BridgeResult<HooksBridge>
    func reach() async -> BridgeResult<ReachBridge>
}

public struct TenantBridge: Sendable {
    public var currentID: String?
    public var listed: [TenantRef]
    public init(currentID: String? = nil, listed: [TenantRef] = []) {
        self.currentID = currentID
        self.listed = listed
    }
}

public struct BlueprintWallsDTO: Codable, Sendable {
    public var network: Bool?
    public var writePaths: [String]?
    public init(network: Bool? = nil, writePaths: [String]? = nil) {
        self.network = network
        self.writePaths = writePaths
    }
}

public struct BlueprintDTO: Codable, Sendable {
    public var slug: String
    public var title: String?
    public var toolbelt: [String]?
    public var walls: BlueprintWallsDTO?
    public init(slug: String, title: String? = nil, toolbelt: [String]? = nil, walls: BlueprintWallsDTO? = nil) {
        self.slug = slug
        self.title = title
        self.toolbelt = toolbelt
        self.walls = walls
    }
}

public struct PlacementRoomDTO: Codable, Sendable {
    public var id: String
    public var blueprintSlug: String?
    public var state: String?
    public var blockedCount: Int?
    public var humanGate: Bool?
    public var occupant: String?
    public var occupantHandle: String?
    public init(
        id: String,
        blueprintSlug: String? = nil,
        state: String? = nil,
        blockedCount: Int? = nil,
        humanGate: Bool? = nil,
        occupant: String? = nil,
        occupantHandle: String? = nil
    ) {
        self.id = id
        self.blueprintSlug = blueprintSlug
        self.state = state
        self.blockedCount = blockedCount
        self.humanGate = humanGate
        self.occupant = occupant
        self.occupantHandle = occupantHandle
    }
}

public struct PlacementDTO: Decodable, Sendable {
    public var id: String
    public var title: String?
    public var state: String?
    public var rooms: [PlacementRoomDTO]?
    public var tenantID: String?
    public var createdAt: Double?
    public var updatedAt: Double?
    public var workdir: String?

    enum CodingKeys: String, CodingKey {
        case id, title, state, rooms, tenantID, createdAt, updatedAt, workdir
    }

    public init(
        id: String, title: String? = nil, state: String? = nil, rooms: [PlacementRoomDTO]? = nil,
        tenantID: String? = nil, createdAt: Double? = nil, updatedAt: Double? = nil, workdir: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.rooms = rooms
        self.tenantID = tenantID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workdir = workdir
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        rooms = try c.decodeIfPresent([PlacementRoomDTO].self, forKey: .rooms)
        tenantID = try c.decodeIfPresent(String.self, forKey: .tenantID)
        workdir = try c.decodeIfPresent(String.self, forKey: .workdir)
        createdAt = Self.lossyTime(c, .createdAt)
        updatedAt = Self.lossyTime(c, .updatedAt)
    }

    private static func lossyTime(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        do {
            return try c.decode(Double.self, forKey: key)
        } catch {}
        do {
            return Double(try c.decode(Int.self, forKey: key))
        } catch {}
        do {
            let s = try c.decode(String.self, forKey: key)
            if let d = ISO8601DateFormatter().date(from: s) {
                return d.timeIntervalSince1970 * 1000
            }
        } catch {}
        return nil
    }
}

public struct SeatDTO: Codable, Sendable {
    public var handle: String
    public var occupant: String?
    public var kind: String?
    public var workdir: String?
    public var model: String?
    public var tier: String?
    public var keys: SeatKeysDTO?
    public var tenant: String? { keys?.tenant }
    public init(handle: String, occupant: String? = nil, kind: String? = nil, workdir: String? = nil, model: String? = nil, tier: String? = nil, keys: SeatKeysDTO? = nil) {
        self.handle = handle
        self.occupant = occupant
        self.kind = kind
        self.workdir = workdir
        self.model = model
        self.tier = tier
        self.keys = keys
    }
}

public struct SeatKeysDTO: Codable, Sendable {
    public var tenant: String?
    public var agentID: String?
    public init(tenant: String? = nil, agentID: String? = nil) {
        self.tenant = tenant
        self.agentID = agentID
    }
}

public struct SessionCardDTO: Decodable, Sendable {
    public var sessionId: String?
    public var tool: String?
    public var cwd: String?
    public var displayTitle: String?
    public var title: String?
    public var lastActive: Double?
    public var messageCount: Int?
    public var inputTokens: Int?
    public var contextWindow: Int?
    public var path: String?

    public init(
        sessionId: String? = nil, tool: String? = nil, cwd: String? = nil,
        displayTitle: String? = nil, title: String? = nil,
        lastActive: Double? = nil, messageCount: Int? = nil,
        inputTokens: Int? = nil, contextWindow: Int? = nil, path: String? = nil
    ) {
        self.sessionId = sessionId
        self.tool = tool
        self.cwd = cwd
        self.displayTitle = displayTitle
        self.title = title
        self.lastActive = lastActive
        self.messageCount = messageCount
        self.inputTokens = inputTokens
        self.contextWindow = contextWindow
        self.path = path
    }

    public var cardName: String {
        let raw = displayTitle ?? title ?? sessionId.map { String($0.prefix(8)) } ?? "세션"
        return raw.isEmpty ? "세션" : raw
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, tool, cwd, displayTitle, title, lastActive, messageCount, inputTokens, contextWindow, path
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
        contextWindow = try c.decodeIfPresent(Int.self, forKey: .contextWindow)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        do {
            let v = try c.decode(Double.self, forKey: .lastActive)
            lastActive = v > 10_000_000_000 ? v / 1000 : v
        } catch {
            do {
                let s = try c.decode(String.self, forKey: .lastActive)
                if let d = ISO8601DateFormatter().date(from: s) {
                    lastActive = d.timeIntervalSince1970
                } else {
                    lastActive = nil
                }
            } catch {
                lastActive = nil
            }
        }
    }
}

public struct AgentDeckStateDTO: Codable, Sendable {
    public var agents: Int?
    public var agentsWorking: Int?
    public var agentsWaiting: Int?
    public var archivedSessions: Int?
    public init(agents: Int? = nil, agentsWorking: Int? = nil, agentsWaiting: Int? = nil, archivedSessions: Int? = nil) {
        self.agents = agents
        self.agentsWorking = agentsWorking
        self.agentsWaiting = agentsWaiting
        self.archivedSessions = archivedSessions
    }
}

public struct ShipJobDTO: Codable, Sendable {
    public var id: String?
    public var dirName: String?
    public var dir: String?
    public var status: String?
    public var state: String?
    public var enqueuedAt: String?
    public var detail: String?

    public var displayName: String { dirName ?? dir ?? id ?? "?" }
    public var jobStatus: String? { status ?? state }

    enum CodingKeys: String, CodingKey {
        case id, dirName, dir, status, state, enqueuedAt, detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        dirName = try container.decodeIfPresent(String.self, forKey: .dirName)
        dir = try container.decodeIfPresent(String.self, forKey: .dir)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        enqueuedAt = Self.decodeTimeField(from: container, key: .enqueuedAt)
    }

    private static func decodeTimeField(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        do {
            return try container.decodeIfPresent(String.self, forKey: key)
        } catch let stringError {
            do {
                if let d = try container.decodeIfPresent(Double.self, forKey: key) {
                    return String(d)
                }
                return nil
            } catch let numError {
                _ = stringError
                _ = numError
                return nil
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(dirName, forKey: .dirName)
        try container.encodeIfPresent(dir, forKey: .dir)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(enqueuedAt, forKey: .enqueuedAt)
        try container.encodeIfPresent(detail, forKey: .detail)
    }

    public init(
        id: String? = nil, dirName: String? = nil, dir: String? = nil,
        status: String? = nil, state: String? = nil, enqueuedAt: String? = nil, detail: String? = nil
    ) {
        self.id = id
        self.dirName = dirName
        self.dir = dir
        self.status = status
        self.state = state
        self.enqueuedAt = enqueuedAt
        self.detail = detail
    }
}

public struct ShipBridge: Sendable {
    public var jobs: [ShipJobDTO]
    public var load1: Double?
    public var ncpu: Int?
    public init(jobs: [ShipJobDTO] = [], load1: Double? = nil, ncpu: Int? = nil) {
        self.jobs = jobs
        self.load1 = load1
        self.ncpu = ncpu
    }
}

public struct VaultBridge: Sendable {
    public var cards: Int
    public var grants: Int
    public var infisical: Int
    public var tenant: String?
    public init(cards: Int, grants: Int, infisical: Int, tenant: String? = nil) {
        self.cards = cards
        self.grants = grants
        self.infisical = infisical
        self.tenant = tenant
    }
}

public struct HostPulse: Sendable {
    public var load1: Double?
    public var memUsedPct: Double?
    public var diskUsedPct: Double?
    public var hang: Int?
    public var live: Int?
    public init(load1: Double? = nil, memUsedPct: Double? = nil, diskUsedPct: Double? = nil, hang: Int? = nil, live: Int? = nil) {
        self.load1 = load1
        self.memUsedPct = memUsedPct
        self.diskUsedPct = diskUsedPct
        self.hang = hang
        self.live = live
    }
}

public struct HookLayerDTO: Decodable, Sendable {
    public var client: String?
    public var layer: String?
    public var hookCount: Int?
    public var isUserImmutable: Bool?
    public var path: String?
    public init(
        client: String? = nil, layer: String? = nil, hookCount: Int? = nil,
        isUserImmutable: Bool? = nil, path: String? = nil
    ) {
        self.client = client
        self.layer = layer
        self.hookCount = hookCount
        self.isUserImmutable = isUserImmutable
        self.path = path
    }

    public var displayName: String {
        [client, layer].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
    }
}

public struct ReachBridge: Sendable {
    public var hasScan: Bool
    public var reached: Int?
    public var unreached: Int?
    public var averageScore: Double?
    public init(hasScan: Bool = false, reached: Int? = nil, unreached: Int? = nil, averageScore: Double? = nil) {
        self.hasScan = hasScan
        self.reached = reached
        self.unreached = unreached
        self.averageScore = averageScore
    }

    public var intNetOK: Bool? {
        guard hasScan, let unreached else { return nil }
        return unreached == 0
    }
}

public struct HooksBridge: Sendable {
    public var ok: Bool
    public var label: String
    public var layers: [HookLayerDTO]
    public var liveGrok: Int?
    public var latestCancel: String?
    public var latestCancelAt: String?
    public init(
        ok: Bool = false, label: String = "", layers: [HookLayerDTO] = [],
        liveGrok: Int? = nil, latestCancel: String? = nil, latestCancelAt: String? = nil
    ) {
        self.ok = ok
        self.label = label
        self.layers = layers
        self.liveGrok = liveGrok
        self.latestCancel = latestCancel
        self.latestCancelAt = latestCancelAt
    }
}

public struct PermissionBridge: Sendable {
    public var summary: String
    public init(summary: String) { self.summary = summary }
}

public struct SkillUsage: Sendable {
    public var callCount: Int
    public var lastCalledAt: Double?
    public var tools: [String]
    public init(callCount: Int, lastCalledAt: Double? = nil, tools: [String] = []) {
        self.callCount = callCount
        self.lastCalledAt = lastCalledAt
        self.tools = tools
    }
}

