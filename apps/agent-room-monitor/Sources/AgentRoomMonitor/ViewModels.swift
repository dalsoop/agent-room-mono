import Foundation
import SwiftUI

/// 뷰 전용 모델 — Core(AgentRoomMonitorCore)에 의존하지 않는다.
/// 프로토타입(`agent-island.html`)의 AGENTS/HOST/FLOWS/EVENTS/TELEM 을 1:1로 옮긴다.
/// Core TwinSnapshot 을 그리는 뷰 모델. 샘플 월드는 두지 않는다.

enum VState: String {
    case neutral, exec, done, block, sleep, gate, queue

    /// 지붕/노드 색.
    var roofColor: Color {
        switch self {
        case .exec: return VColor.exec
        case .block: return VColor.bad
        case .gate: return VColor.gate
        case .sleep: return Color(red: 0x46 / 255, green: 0x53 / 255, blue: 0x6E / 255)
        default: return Color(red: 0x77 / 255, green: 0x82 / 255, blue: 0x8F / 255)
        }
    }

    /// 사용자 노출 라벨은 L10n 경유 — 하드코딩 금지.
    var l10nKey: L10nKey {
        switch self {
        case .exec: return .stateExec
        case .done: return .stateDone
        case .block: return .stateBlock
        case .sleep: return .stateSleep
        case .gate: return .stateGate
        case .queue: return .stateQueue
        case .neutral: return .stateNeutral
        }
    }
}

/// 색 규율: 중립 남회색 램프 + 의미색 3(실행/문제/게이트) + 강조 1(시안, 흐름·선택 전용)
enum VColor {
    static let exec = Color(red: 0x3E / 255, green: 0xCF / 255, blue: 0x7B / 255)
    static let bad = Color(red: 0xE4 / 255, green: 0x57 / 255, blue: 0x4C / 255)
    static let gate = Color(red: 0xE9 / 255, green: 0xB8 / 255, blue: 0x4C / 255)
    static let accent = Color(red: 0x6F / 255, green: 0xD3 / 255, blue: 0xE8 / 255)
    static let body = Color(red: 0x6E / 255, green: 0x79 / 255, blue: 0x87 / 255)
    static let sea0 = Color(red: 0x15 / 255, green: 0x22 / 255, blue: 0x2E / 255)
    static let sea1 = Color(red: 0x0E / 255, green: 0x18 / 255, blue: 0x22 / 255)
    static let floor: [Color] = [
        Color(red: 0x39 / 255, green: 0x43 / 255, blue: 0x4F / 255),
        Color(red: 0x41 / 255, green: 0x4D / 255, blue: 0x5A / 255),
        Color(red: 0x4A / 255, green: 0x57 / 255, blue: 0x64 / 255),
    ]
}

struct VAgent {
    var emoji: String
    var name: String
    var tool: String
    var model: String
    var env: String
}

struct VDecision: Identifiable {
    var id: String
    var title: String
    var done: Bool
}

/// 만능 부착 타일 — 스킬·장비·회선 등. 값·버전 관리.
struct VAttachment: Identifiable {
    var id: String { "\(kind):\(name)" }
    var kind: String
    var name: String
    var value: String?
    var version: String?
    var callCount: Int?
    var lastCalledAt: Double?
    var tools: [String]?

    var isCalled: Bool { (callCount ?? 0) > 0 }

    /// 위성 헥스에 찍는 글리프 — kind 별 데이터 테이블.
    var glyph: String {
        switch kind {
        case "skill": return "S"
        case "equipment": return "E"
        case "net": return "N"
        default: return "•"
        }
    }
}

/// 방/건물 하나. class — 트리 구조를 참조로 공유(레이아웃 엔진이 id 로 인덱싱).
final class VNode: Identifiable {
    let id: String
    var name: String
    var icon: String
    /// Core TwinKind rawValue — 뷰 동작(zone=군집, 그 외=섬)은 이 값으로만 분기. id 추측 금지.
    var kindRaw: String
    var leaseName: String?
    var leaseDetail: String?
    var attachments: [VAttachment]
    var blueprint: String
    var state: VState
    var healthBlocked: Int
    var healthNotes: [String]
    var agentKey: String?
    var session: String?
    var tokens: Int
    var maxTokens: Int
    var skills: [String]
    var verify: String?
    var decisions: [VDecision]
    var tenantID: String?
    var viewpoint: String?
    var children: [VNode]

    init(
        id: String,
        name: String,
        icon: String,
        kindRaw: String = "room",
        leaseName: String? = nil,
        leaseDetail: String? = nil,
        attachments: [VAttachment] = [],
        blueprint: String = "",
        state: VState = .neutral,
        healthBlocked: Int = 0,
        healthNotes: [String] = [],
        agentKey: String? = nil,
        session: String? = nil,
        tokens: Int = 0,
        maxTokens: Int = 0,
        skills: [String] = [],
        verify: String? = nil,
        decisions: [VDecision] = [],
        tenantID: String? = nil,
        viewpoint: String? = nil,
        children: [VNode] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.kindRaw = kindRaw
        self.leaseName = leaseName
        self.leaseDetail = leaseDetail
        self.attachments = attachments
        self.blueprint = blueprint
        self.state = state
        self.healthBlocked = healthBlocked
        self.healthNotes = healthNotes
        self.agentKey = agentKey
        self.session = session
        self.tokens = tokens
        self.maxTokens = maxTokens
        self.skills = skills
        self.verify = verify
        self.decisions = decisions
        self.tenantID = tenantID
        self.viewpoint = viewpoint
        self.children = children
    }

    /// 건물 헤더 pawn — 자손 입주 키 앞에서 몇 개만.
    func occupantKeys(limit: Int = 4) -> [String] {
        var out: [String] = []
        func walk(_ node: VNode) {
            if out.count >= limit { return }
            if let key = node.agentKey, !out.contains(key) { out.append(key) }
            for child in node.children { walk(child) }
        }
        walk(self)
        return out
    }

    /// 재귀 집계 — 자손의 block/gate/exec 개수(자기 자신 상태 포함, 자식부터).
    func aggregate() -> (exec: Int, block: Int, gate: Int) {
        var a = (exec: 0, block: 0, gate: 0)
        for c in children {
            let b = c.aggregate()
            a.block += b.block + (c.state == .block ? 1 : 0)
            a.gate += b.gate + (c.state == .gate ? 1 : 0)
            a.exec += b.exec + (c.state == .exec ? 1 : 0)
        }
        return a
    }

    func find(_ targetID: String) -> VNode? {
        if id == targetID { return self }
        for c in children {
            if let f = c.find(targetID) { return f }
        }
        return nil
    }
}

struct VFlow: Identifiable {
    var id: String { "\(from)->\(to)#\(no)" }
    var from: String
    var to: String
    var no: Int
    var label: String
    var state: VState

    var lineColor: Color {
        switch state {
        case .block: return VColor.bad
        case .gate: return VColor.gate
        case .queue: return Color(red: 0x8C / 255, green: 0xA0 / 255, blue: 0xB3 / 255)
        default: return VColor.accent
        }
    }
}

struct VTelemetry {
    var load1: Double
    var ncpu: Int
    var memUsed: Int
    var memTot: Int
    var downKB: Int
    var upKB: Int
    var intNet: Bool
    var extNet: Bool
    var at: String
}

struct VTraceEvent: Identifiable {
    let id = UUID()
    var t: Double
    var lane: Int
    var dur: Double
    var label: String
    var state: VState
    var dashed: Bool
    var detail: String?
    var diamond: Bool
    var roomID: String?
    var sessionID: String?
    var sourcePath: String?

    init(
        t: Double, lane: Int, dur: Double = 0, label: String, state: VState = .neutral,
        dashed: Bool = false, detail: String? = nil, diamond: Bool = false,
        roomID: String? = nil, sessionID: String? = nil, sourcePath: String? = nil
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

/// 렌더러가 소비하는 전체 세계.
struct VWorld {
    var agents: [String: VAgent]
    var appView: [String: String]
    var netView: [String: String]
    var telemetry: VTelemetry
    var iconOf: [String: String]
    var host: VNode
    var flows: [VFlow]
    var born: [String: Double]
    var lanes: [String]
    var events: [VTraceEvent]
    var tMax: Double
    var tenants: [VTenant]
    var currentTenantID: String?
}

struct VTenant: Identifiable {
    var id: String
    var displayName: String
    var current: Bool
}

extension VWorld {
    func find(_ id: String) -> VNode? {
        host.find(id)
    }
}


