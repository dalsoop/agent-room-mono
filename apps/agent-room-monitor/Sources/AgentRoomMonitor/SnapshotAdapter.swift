import AgentRoomMonitorCore
import Foundation

/// Core TwinSnapshot(실데이터) → 뷰 모델(VWorld) 변환.
/// 하드코딩 샘플 금지(사용자 결정 2026-08-20) — 화면의 모든 것은 이 어댑터를 거친 실측이다.
enum SnapshotAdapter {
    static func emptyWorld() -> VWorld {
        VWorld(
            agents: [:], appView: [:], netView: [:],
            telemetry: VTelemetry(load1: 0, ncpu: 0, memUsed: 0, memTot: 0, downKB: 0, upKB: 0, intNet: false, extNet: false, at: ""),
            iconOf: [:],
            host: VNode(id: "host", name: "", icon: ""),
            flows: [], born: [:], lanes: [],
            events: [], tMax: 1, tenants: [], currentTenantID: nil
        )
    }

    static func vworld(from snap: TwinSnapshot) -> VWorld {
        var agents: [String: VAgent] = [:]
        var appView: [String: String] = [:]
        var netView: [String: String] = [:]
        var iconOf: [String: String] = [:]
        var bornMap: [String: Double] = [:]

        func convert(_ n: TwinNode) -> VNode {
            if let a = n.agent {
                agents[n.id] = VAgent(
                    emoji: emoji(for: a.tool),
                    name: a.actor,
                    tool: a.tool ?? "?",
                    model: a.model ?? "?",
                    env: a.env ?? "—"
                )
            }
            if let av = n.appView { appView[n.id] = av }
            if let net = n.net {
                if net.externalOK == true { netView[n.id] = "ext" }
                else if net.internalOK == true { netView[n.id] = "int" }
            }
            /* 마스코트는 Core MascotRegistry 발급분만 — 뷰 추측 금지 */
            if let key = n.mascot { iconOf[n.id] = key }
            if n.born > 0 { bornMap[n.id] = n.born }
            return VNode(
                id: n.id,
                name: n.name,
                icon: n.icon ?? "▫️",
                kindRaw: n.kind.rawValue,
                leaseName: n.lease?.appName,
                leaseDetail: n.lease?.detail,
                attachments: n.attachments.map {
                    VAttachment(kind: $0.kind, name: $0.name, value: $0.value, version: $0.version,
                                callCount: $0.callCount, lastCalledAt: $0.lastCalledAt, tools: $0.tools)
                },
                blueprint: n.blueprintSlug ?? "",
                state: VState(rawValue: n.state.rawValue) ?? .neutral,
                healthBlocked: n.health.blocked,
                healthNotes: n.health.notes,
                agentKey: n.agent != nil ? n.id : nil,
                session: n.agent?.sessionID,
                tokens: n.tokens ?? 0,
                maxTokens: n.maxTokens ?? 0,
                skills: n.skills,
                verify: n.verify,
                decisions: n.decisions.map { VDecision(id: $0.id, title: $0.title, done: $0.done) },
                tenantID: n.tenantID,
                viewpoint: n.viewpoint,
                children: n.children.map(convert)
            )
        }

        let host = convert(snap.root)
        let tele = snap.telemetry
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let events = snap.trace.map {
            VTraceEvent(t: $0.t, lane: $0.lane, dur: $0.dur ?? 0, label: $0.label,
                        state: VState(rawValue: $0.state.rawValue) ?? .neutral,
                        dashed: $0.dashed, detail: $0.detail, diamond: $0.diamond,
                        roomID: $0.roomID, sessionID: $0.sessionID, sourcePath: $0.sourcePath)
        }
        let maxT = events.map(\.t).max() ?? Date().timeIntervalSince1970

        return VWorld(
            agents: agents,
            appView: appView,
            netView: netView,
            telemetry: VTelemetry(
                load1: tele.load1 ?? 0,
                ncpu: tele.ncpu ?? 0,
                memUsed: Int((tele.memUsedGB ?? 0).rounded()),
                memTot: Int((tele.memTotGB ?? 0).rounded()),
                downKB: Int((tele.downKBps ?? 0).rounded()),
                upKB: Int((tele.upKBps ?? 0).rounded()),
                intNet: tele.intNetOK ?? false,
                extNet: tele.extNetOK ?? false,
                at: df.string(from: Date(timeIntervalSince1970: tele.at))
            ),
            iconOf: iconOf,
            host: host,
            flows: snap.flows.map { VFlow(from: $0.from, to: $0.to, no: $0.no, label: $0.label, state: VState(rawValue: $0.state.rawValue) ?? .neutral) },
            born: bornMap,  // 실시각(epoch) — placement createdAt·ship enqueuedAt·seat hiredAt
            lanes: ["발언·지시", "도구 호출", "서브에이전트", "산출물·결정", "미호출 스킬"],
            events: events,
            tMax: max(1, maxT),
            tenants: snap.tenants.map { VTenant(id: $0.id, displayName: $0.displayName, current: $0.current) },
            currentTenantID: snap.currentTenantID
        )
    }

    private static func emoji(for tool: String?) -> String {
        switch tool {
        case "claude": return "🤖"
        case "codex": return "📦"
        case "grok": return "🦊"
        case "agy": return "✈️"
        default: return "⚙️"
        }
    }

}
