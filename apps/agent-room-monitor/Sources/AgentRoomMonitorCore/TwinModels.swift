import Foundation

/// 디지털 트윈 재귀 모델 — 화면=실제 투영 전부 (위키 913d45ec 요구사항 A.1/A.2).
/// 방·자리·스킬·세션·호스트 실데이터를 하나의 스냅샷으로 미러링한다.

public enum NodeState: String, Codable, Sendable, Equatable {
    case exec
    case done
    case block
    case sleep
    case gate
    case queue
    case neutral
}

/// 노드 종류 — 뷰가 id 문자열로 추측하지 않도록 타입으로 고정한다 (하드코딩 금지 규율).
public enum TwinKind: String, Codable, Sendable, Equatable {
    case host        // 이 맥
    case zone        // 군집(보기 편의 그룹) — 섬이 아니라 이웃 배치 단위
    case placement   // 배치도 — 독립 섬
    case room        // 방 — 부모 섬 안의 작은 섬
    case seat        // 에이전트 자리 — 독립 섬
    case warehouse   // 소유 컨테이너(스킬 창고 등) — 한 섬, 자식은 안의 작은 섬
    case skill       // 스킬 항목
    case app         // 앱 섬 — 방들이 임대하는 자원, 큐를 품는다
    case queueItem   // 앱 섬 안의 큐 항목
}

/// 만능 부착 타일 — 스킬·장비·회선 등 무엇이든 섬에 붙는 단위. 값·버전을 가진다.
public struct TwinAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kind):\(name)" }
    public var kind: String      // "skill" | "equipment" | "net" | "model" …
    public var name: String
    public var value: String?    // 관리 값 (예: 속도, 비용, 상한)
    public var version: String?  // 타일 버전
    /// 호출 기록 — session-context-ledger 실측 (주입+터치 세션 수).
    public var callCount: Int?
    public var lastCalledAt: Double?   // unix epoch seconds
    /// 이 타일을 실제로 문 하네스들 (claude/grok/codex …).
    public var tools: [String]?

    public init(
        kind: String, name: String, value: String? = nil, version: String? = nil,
        callCount: Int? = nil, lastCalledAt: Double? = nil, tools: [String]? = nil
    ) {
        self.kind = kind
        self.name = name
        self.value = value
        self.version = version
        self.callCount = callCount
        self.lastCalledAt = lastCalledAt
        self.tools = tools
    }
}

/// 임대 — 방이 앱(작업 공간)을 빌려 쓰는 관계.
public struct TwinLease: Codable, Sendable, Equatable {
    public var appName: String
    public var detail: String?

    public init(appName: String, detail: String? = nil) {
        self.appName = appName
        self.detail = detail
    }
}

public struct TwinAgent: Codable, Sendable, Equatable {
    /// 예: "agent:claude-code@macbook" — 별명 금지, 실체 표기(요구사항 D.18).
    public var actor: String
    public var sessionID: String?
    public var tool: String?
    public var model: String?
    public var env: String?

    public init(actor: String, sessionID: String? = nil, tool: String? = nil, model: String? = nil, env: String? = nil) {
        self.actor = actor
        self.sessionID = sessionID
        self.tool = tool
        self.model = model
        self.env = env
    }
}

public struct TwinHealth: Codable, Sendable, Equatable {
    public var blocked: Int
    public var notes: [String]

    public init(blocked: Int = 0, notes: [String] = []) {
        self.blocked = blocked
        self.notes = notes
    }
}

public struct TwinDecision: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var done: Bool

    public init(id: String, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

public struct NetFace: Codable, Sendable, Equatable {
    /// 요구사항 F.25 — 방별 내부망/외부망 도달성 면.
    public var internalOK: Bool?
    public var externalOK: Bool?

    public init(internalOK: Bool? = nil, externalOK: Bool? = nil) {
        self.internalOK = internalOK
        self.externalOK = externalOK
    }
}

public final class TwinNode: Codable, @unchecked Sendable {
    public var id: String
    public var name: String
    public var icon: String?
    /// 종류 — 뷰 동작(섬/군집/타워)은 이 타입이 결정한다. id 문자열 추측 금지.
    public var kind: TwinKind
    /// 마스코트 키 — Core MascotRegistry 가 발급. 뷰에서 slug 추측 금지.
    public var mascot: String?
    /// 임대 중인 앱(작업 공간).
    public var lease: TwinLease?
    /// 부착 타일 — 실행 시점에 붙는 스킬·장비·회선 등.
    public var attachments: [TwinAttachment]
    public var blueprintSlug: String?
    public var state: NodeState
    public var health: TwinHealth
    public var agent: TwinAgent?
    public var tokens: Int?
    public var maxTokens: Int?
    public var skills: [String]
    public var appView: String?
    public var net: NetFace?
    /// 등장 시각(unix epoch seconds) — 요구사항 C.13 시점 스크러버의 born 필터용.
    public var born: Double
    public var verify: String?
    public var decisions: [TwinDecision]
    /// 테넌트 격리 정본 id. 없으면 미분류.
    public var tenantID: String?
    /// `first` = 이 테넌트가 겪는 자리/방, `third` = 관측되는 다른 에이전트·함대.
    public var viewpoint: String?
    public var children: [TwinNode]

    public init(
        id: String,
        name: String,
        icon: String? = nil,
        kind: TwinKind = .room,
        mascot: String? = nil,
        lease: TwinLease? = nil,
        attachments: [TwinAttachment] = [],
        blueprintSlug: String? = nil,
        state: NodeState = .neutral,
        health: TwinHealth = TwinHealth(),
        agent: TwinAgent? = nil,
        tokens: Int? = nil,
        maxTokens: Int? = nil,
        skills: [String] = [],
        appView: String? = nil,
        net: NetFace? = nil,
        born: Double = Date().timeIntervalSince1970,
        verify: String? = nil,
        decisions: [TwinDecision] = [],
        tenantID: String? = nil,
        viewpoint: String? = nil,
        children: [TwinNode] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.kind = kind
        self.mascot = mascot
        self.lease = lease
        self.attachments = attachments
        self.blueprintSlug = blueprintSlug
        self.state = state
        self.health = health
        self.agent = agent
        self.tokens = tokens
        self.maxTokens = maxTokens
        self.skills = skills
        self.appView = appView
        self.net = net
        self.born = born
        self.verify = verify
        self.decisions = decisions
        self.tenantID = tenantID
        self.viewpoint = viewpoint
        self.children = children
    }

    /// 디코딩 호환 — 과거 스냅샷(JSON)에 kind 가 없으면 room 으로.
    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        kind = try c.decodeIfPresent(TwinKind.self, forKey: .kind) ?? .room
        mascot = try c.decodeIfPresent(String.self, forKey: .mascot)
        lease = try c.decodeIfPresent(TwinLease.self, forKey: .lease)
        attachments = try c.decodeIfPresent([TwinAttachment].self, forKey: .attachments) ?? []
        blueprintSlug = try c.decodeIfPresent(String.self, forKey: .blueprintSlug)
        state = try c.decode(NodeState.self, forKey: .state)
        health = try c.decode(TwinHealth.self, forKey: .health)
        agent = try c.decodeIfPresent(TwinAgent.self, forKey: .agent)
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
        appView = try c.decodeIfPresent(String.self, forKey: .appView)
        net = try c.decodeIfPresent(NetFace.self, forKey: .net)
        born = try c.decodeIfPresent(Double.self, forKey: .born) ?? 0
        verify = try c.decodeIfPresent(String.self, forKey: .verify)
        decisions = try c.decodeIfPresent([TwinDecision].self, forKey: .decisions) ?? []
        tenantID = try c.decodeIfPresent(String.self, forKey: .tenantID)
        viewpoint = try c.decodeIfPresent(String.self, forKey: .viewpoint)
        children = try c.decodeIfPresent([TwinNode].self, forKey: .children) ?? []
    }
}

/// 마스코트 발급 레지스트리 — 규칙을 데이터(테이블)로 소유한다. 뷰/어댑터에 분산 금지.
public enum MascotRegistry {
    /// (blueprintSlug 부분일치, 마스코트 키) — 순서 = 우선순위.
    public static let slugRules: [(contains: String, key: String)] = [
        ("command", "command"),
        ("fleet", "fleet"),
        ("doctor", "night"),
        ("verdict", "review"),
        ("investigation", "bot-scout"),
        ("scale", "bot-builder"),
        ("self-proof", "bot-miner"),
        ("wiring", "bot-builder"),
    ]

    public static let kindDefaults: [TwinKind: String] = [
        .host: "command",
        .zone: "fleet",
        .placement: "work",
        .room: "work",
        .seat: "session",
        .warehouse: "skills",
        .skill: "skill-ok",
        .app: "facility",
        .queueItem: "work",
    ]

    public static func key(kind: TwinKind, blueprintSlug: String?) -> String? {
        if let slug = blueprintSlug {
            for rule in slugRules where slug.contains(rule.contains) {
                return rule.key
            }
        }
        return kindDefaults[kind]
    }
}

extension TwinNode: Equatable {
    public static func == (lhs: TwinNode, rhs: TwinNode) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.state == rhs.state
            && lhs.children.map(\.id) == rhs.children.map(\.id)
    }
}

public struct TwinFlow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(from)->\(to)#\(no)" }
    public var from: String
    public var to: String
    public var no: Int
    public var label: String
    public var state: NodeState

    public init(from: String, to: String, no: Int, label: String, state: NodeState) {
        self.from = from
        self.to = to
        self.no = no
        self.label = label
        self.state = state
    }
}

public struct HostTelemetry: Codable, Sendable, Equatable {
    public var load1: Double?
    public var ncpu: Int?
    public var memUsedGB: Double?
    public var memTotGB: Double?
    public var downKBps: Double?
    public var upKBps: Double?
    public var intNetOK: Bool?
    public var extNetOK: Bool?
    public var at: Double

    public init(
        load1: Double? = nil,
        ncpu: Int? = nil,
        memUsedGB: Double? = nil,
        memTotGB: Double? = nil,
        downKBps: Double? = nil,
        upKBps: Double? = nil,
        intNetOK: Bool? = nil,
        extNetOK: Bool? = nil,
        at: Double = Date().timeIntervalSince1970
    ) {
        self.load1 = load1
        self.ncpu = ncpu
        self.memUsedGB = memUsedGB
        self.memTotGB = memTotGB
        self.downKBps = downKBps
        self.upKBps = upKBps
        self.intNetOK = intNetOK
        self.extNetOK = extNetOK
        self.at = at
    }
}

public struct TraceEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(t)-\(lane)-\(label)-\(roomID ?? "")" }
    /// 시각(unix epoch seconds).
    public var t: Double
    /// 스윔레인 0~4 (요구사항 C.12): 0=발언·지시, 1=도구 호출, 2=서브에이전트, 3=산출물·결정, 4=미호출 스킬.
    public var lane: Int
    public var dur: Double?
    public var label: String
    public var state: NodeState
    public var dashed: Bool
    public var detail: String?
    public var diamond: Bool
    /// 이 span 이 속한 방 — 시점 모드는 현재 방만 그린다 (C.11).
    public var roomID: String?
    public var sessionID: String?
    /// TranscriptReader 가 열 원문 경로.
    public var sourcePath: String?

    public init(
        t: Double,
        lane: Int,
        dur: Double? = nil,
        label: String,
        state: NodeState = .neutral,
        dashed: Bool = false,
        detail: String? = nil,
        diamond: Bool = false,
        roomID: String? = nil,
        sessionID: String? = nil,
        sourcePath: String? = nil
    ) {
        self.t = t
        self.lane = lane
        self.dur = dur
        self.label = label
        self.state = state
        self.dashed = dashed
        self.detail = detail
        self.diamond = diamond
        self.roomID = roomID
        self.sessionID = sessionID
        self.sourcePath = sourcePath
    }
}

public struct TenantRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var current: Bool
    public init(id: String, displayName: String, current: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.current = current
    }
}

public struct TwinSnapshot: Codable, Sendable {
    public var root: TwinNode
    public var flows: [TwinFlow]
    public var telemetry: HostTelemetry
    public var trace: [TraceEvent]
    public var generatedAt: Date
    public var tenants: [TenantRef]
    public var currentTenantID: String?

    public init(
        root: TwinNode,
        flows: [TwinFlow],
        telemetry: HostTelemetry,
        trace: [TraceEvent],
        generatedAt: Date = Date(),
        tenants: [TenantRef] = [],
        currentTenantID: String? = nil
    ) {
        self.root = root
        self.flows = flows
        self.telemetry = telemetry
        self.trace = trace
        self.generatedAt = generatedAt
        self.tenants = tenants
        self.currentTenantID = currentTenantID
    }
}
