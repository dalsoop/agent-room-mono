import SwiftUI
import AgentRoomMonitorCore

/// 우측 슬라이드 상세 패널 — 방/건물 클릭 시. 문자열은 전부 L10n 경유.
struct DetailPanelView: View {
    @Environment(AppModel.self) private var app
    let node: VNode
    let world: VWorld
    let root: VNode
    let board: BoardModel
    let close: () -> Void
    var enter: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                enterButton
                operateSection
                occupantSection
                appViewSection
                axSection
                netSection
                flowSection
                attachmentsSection
                healthSection
                skillsSection
                DetailPanelVaultSection(node: node)
                childrenSection
                decisionsSection
                verifySection
            }
            .padding(20)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Image(systemName: "xmark").foregroundStyle(.secondary) }
                .buttonStyle(.plain).padding(12)
        }
    }

    // MARK: 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(node.icon) \(node.name)").font(.system(size: 16, weight: .bold))
            Text(subtitle)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(red: 0.39, green: 0.47, blue: 0.55))
            HStack(spacing: 6) {
                badge(app.L(node.state.l10nKey), node.state.roofColor)
                blockedBadge
                gateBadge
            }
        }
    }

    private var subtitle: String {
        let blueprint = node.blueprint.isEmpty ? "—" : node.blueprint
        guard let session = node.session else { return blueprint }
        return "\(blueprint) · session=\(session)"
    }

    @ViewBuilder private var blockedBadge: some View {
        if node.healthBlocked > 0 {
            badge(String(format: app.L(.panelBlockedTimes), node.healthBlocked), VColor.bad)
        }
    }

    @ViewBuilder private var gateBadge: some View {
        if node.state == .gate {
            badge(app.L(.panelHumanGate), VColor.gate)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10.5))
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: 섹션들

    @ViewBuilder private var enterButton: some View {
        if let enter {
            Button(action: enter) {
                Label(app.L(.boardEnter), systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(app.L(.boardEnterHelp))
            .accessibilityIdentifier("enter-room")
        }
    }

    @ViewBuilder private var operateSection: some View {
        section(app.L(.panelOperate)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if node.kindRaw == "room" || node.kindRaw == "placement" {
                        Button(app.L(.panelOccupy)) {
                            Task { await occupy() }
                        }.controlSize(.small)
                        Button(app.L(.panelTick)) {
                            Task { await tickPlan() }
                        }.controlSize(.small)
                    }
                    if node.kindRaw == "placement" || node.kindRaw == "room" {
                        Button(app.L(.panelDemolish)) {
                            Task { await demolish() }
                        }.controlSize(.small)
                    }
                    if node.kindRaw == "skill" {
                        Button(app.L(.panelOpenSkill)) {
                            Task {
                                await board.operate(.openSkill(
                                    name: node.name,
                                    skillsDir: FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent(".codex/skills", isDirectory: true)
                                ))
                            }
                        }.controlSize(.small)
                    }
                }
                if node.session != nil || node.maxTokens > 0 {
                    HStack {
                        Button(app.L(.panelHandoffPack)) {
                            Task { await packHandoff() }
                        }.controlSize(.small)
                        Button(app.L(.panelHandoffResume)) {
                            Task { await resumeHandoff() }
                        }.controlSize(.small)
                    }
                }
                if let msg = board.lastOperate {
                    Text(msg)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(board.lastOperateOK ? VColor.exec : VColor.bad)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func planID() -> String? {
        if node.kindRaw == "placement" { return node.id.hasPrefix("lobby-") ? String(node.id.dropFirst(6)) : node.id }
        return board.parent(of: node)?.id
    }

    private func occupy() async {
        guard let plan = planID() else { return }
        let room = node.kindRaw == "room" ? node.id : (node.children.first?.id ?? node.id)
        await board.operate(.occupy(planID: plan, roomID: room, occupant: board.defaultOccupant()))
    }

    private func tickPlan() async {
        guard let plan = planID() else { return }
        await board.operate(.tick(planID: plan))
    }

    private func demolish() async {
        if node.kindRaw == "placement" {
            await board.operate(.rejectPlacement(planID: planID() ?? node.id, by: "agent-room-monitor"))
        } else if !node.blueprint.isEmpty {
            await board.operate(.demolishBlueprint(slug: node.blueprint))
        }
    }

    private func packHandoff() async {
        guard let session = node.session, !session.isEmpty else { return }
        await board.operate(.handoffPack(sessionID: session))
    }

    private func resumeHandoff() async {
        guard let session = node.session, !session.isEmpty else { return }
        guard let tool = world.agents[node.agentKey ?? ""]?.tool, !tool.isEmpty, tool != "?" else { return }
        await board.operate(.handoffResume(sessionID: session, to: tool))
    }

    @ViewBuilder private var axSection: some View {
        let appName = node.leaseName ?? world.appView[node.id]
        if let appName, !appName.isEmpty {
            section(app.L(.panelAX)) {
                VStack(alignment: .leading, spacing: 6) {
                    Button(app.L(.panelAXLoad)) {
                        Task { await board.loadAX(appName: appName) }
                    }
                    .controlSize(.small)
                    if board.axApp == appName, let text = board.axText {
                        Text(text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder private var occupantSection: some View {
        if let key = node.agentKey, let agent = world.agents[key] {
            section(app.L(.panelOccupant)) {
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(agent.emoji) ").font(.system(size: 13)) + Text(agent.name).bold()
                        Text("\(agent.tool) · \(agent.model)\n\(agent.env)")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        tokenGauge(agent)
                    }
                }
            }
        } else if let lease = node.leaseName, !lease.isEmpty {
            section(app.L(.panelOccupant)) {
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lease).bold()
                        if let detail = node.leaseDetail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func tokenGauge(_ agent: VAgent) -> some View {
        if node.maxTokens > 0 {
            let ratio = Double(node.tokens) / Double(node.maxTokens)
            let color: Color = ratio > 0.9 ? VColor.bad : (ratio > 0.7 ? VColor.gate : VColor.exec)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, ratio))
                }
            }
            .frame(height: 7)
            HStack {
                Text(app.L(.panelContextNote))
                Spacer()
                Text("\(node.tokens / 1000)k/\(node.maxTokens / 1000)k")
            }
            .font(.system(size: 10.5)).foregroundStyle(.secondary)
            handoffAlert(agent, ratio: ratio)
        }
    }

    @ViewBuilder private func handoffAlert(_ agent: VAgent, ratio: Double) -> some View {
        if ratio > 0.9 {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.L(.panelHandoffTitle)).bold()
                Text(String(format: app.L(.panelHandoffCmd), agent.tool))
                    .font(.system(size: 10.5, design: .monospaced))
            }
            .padding(9)
            .background(VColor.bad.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(VColor.bad.opacity(0.4)))
            .foregroundStyle(Color(red: 1, green: 0.69, blue: 0.65))
        }
    }

    @ViewBuilder private var appViewSection: some View {
        if let appView = world.appView[node.id] {
            section(app.L(.panelAppView)) {
                card { Text("📂 \(appView)").monospaced() }
            }
        }
    }

    @ViewBuilder private var netSection: some View {
        if let net = world.netView[node.id] {
            section(app.L(.panelNet)) {
                card { Text(net == "ext" ? app.L(.panelNetExt) : app.L(.panelNetInt)) }
            }
        }
    }

    private var nodeFlows: [VFlow] {
        world.flows
            .filter { $0.from == node.id || $0.to == node.id }
            .sorted { $0.no < $1.no }
    }

    @ViewBuilder private var flowSection: some View {
        if !nodeFlows.isEmpty {
            section(app.L(.panelFlows)) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(nodeFlows) { flow in
                        flowRow(flow)
                    }
                }
            }
        }
    }

    private func flowRow(_ flow: VFlow) -> some View {
        let isOutgoing = flow.from == node.id
        let otherID = isOutgoing ? flow.to : flow.from
        let otherName = root.find(otherID)?.name ?? otherID
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(flow.no > 0 ? "\(flow.no)" : "·")
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(VColor.accent)
            Text("\(isOutgoing ? "→" : "←") ").font(.system(size: 12))
                + Text(otherName).bold()
                + Text(" — \(flow.label)").font(.system(size: 12))
        }
    }

    @ViewBuilder private var attachmentsSection: some View {
        if !node.attachments.isEmpty {
            section(String(format: app.L(.panelAttachments), node.attachments.count)) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.attachments) { tile in
                        HStack(spacing: 8) {
                            Text(tile.glyph)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .frame(width: 16, height: 16)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            Text(tile.name).monospaced().font(.system(size: 12))
                                .foregroundStyle(tile.kind == "skill" && !tile.isCalled ? Color.secondary : Color.primary)
                            Spacer()
                            if let count = tile.callCount, count > 0 {
                                Text(String(format: app.L(.panelCalls), count))
                                    .font(.system(size: 10.5)).foregroundStyle(VColor.exec)
                            }
                            if let tools = tile.tools, !tools.isEmpty {
                                Text(tools.joined(separator: "·"))
                                    .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            if let value = tile.value {
                                Text(value).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            if let version = tile.version {
                                Text("v\(version)").font(.system(size: 10, design: .monospaced)).foregroundStyle(VColor.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var healthSection: some View {
        if !node.healthNotes.isEmpty {
            section(app.L(.panelHealth)) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(node.healthNotes, id: \.self) { note in card { Text(note) } }
                }
            }
        }
    }

    @ViewBuilder private var skillsSection: some View {
        if !node.skills.isEmpty {
            section(String(format: app.L(.panelSkills), node.skills.count)) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.skills, id: \.self) { skill in
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: 0x77 / 255, green: 0x82 / 255, blue: 0x8F / 255))
                                .frame(width: 8, height: 8)
                            Text(skill).monospaced().font(.system(size: 12))
                                .foregroundStyle(Color(red: 0.78, green: 0.82, blue: 0.86))
                        }
                    }
                }
            }
        }
    }



    @ViewBuilder private var childrenSection: some View {
        if !node.children.isEmpty {
            section(String(format: app.L(.panelChildren), node.children.count)) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(node.children) { child in
                        HStack(spacing: 8) {
                            Circle().fill(child.state.roofColor).frame(width: 8, height: 8)
                            Text(child.icon + " ") + Text(child.name).bold()
                                + Text(" — \(app.L(child.state.l10nKey))")
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
    }

    @ViewBuilder private var decisionsSection: some View {
        if !node.decisions.isEmpty {
            section(app.L(.panelDecisions)) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(node.decisions) { decision in
                        card {
                            HStack {
                                Text(decision.id).monospaced().font(.system(size: 11))
                                Text(decision.title)
                                Spacer()
                                Text(decision.done ? "✓" : app.L(.panelPending))
                                    .foregroundStyle(decision.done ? VColor.exec : VColor.gate)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var verifySection: some View {
        if let verify = node.verify {
            section(app.L(.panelVerify)) {
                Text(verify)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(red: 0.61, green: 0.78, blue: 0.68))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15)))
            }
        }
    }

    // MARK: 빌딩 블록

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10.5))
                .foregroundStyle(Color(red: 0.39, green: 0.47, blue: 0.55))
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 12))
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
    }
}

/// trace span 클릭 상세.
struct SpanDetailView: View {
    @Environment(AppModel.self) private var app
    let span: VTraceEvent
    let excerpts: [TranscriptLookup.Excerpt]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            timeRow
            uncalledBadge
            detailSection
            realWiringSection
            Spacer()
        }
        .padding(20)
    }

    private var headerRow: some View {
        HStack {
            Text("\(span.diamond ? "◆" : "▬") \(span.label)").font(.system(size: 16, weight: .bold))
            Spacer()
            Button(action: close) { Image(systemName: "xmark").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
        }
    }

    private var timeRow: some View {
        let end = span.dur > 0 ? " ~ \(String(format: "%.1f", span.t + span.dur))" : ""
        let laneName = TraceLane(rawValue: span.lane).map { app.L($0.l10nKey) } ?? ""
        return Text("t \(String(format: "%.1f", span.t))\(end) · \(laneName)")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color(red: 0.39, green: 0.47, blue: 0.55))
    }

    @ViewBuilder private var uncalledBadge: some View {
        if span.dashed {
            Text(app.L(.spanUncalled)).font(.system(size: 10.5))
                .padding(.horizontal, 9).padding(.vertical, 2)
                .background(VColor.gate.opacity(0.14), in: Capsule())
                .foregroundStyle(VColor.gate)
        }
    }

    @ViewBuilder private var detailSection: some View {
        if let detail = span.detail {
            labeledCard(app.L(.spanDetail), detail)
        }
    }

    @ViewBuilder private var realWiringSection: some View {
        if excerpts.isEmpty {
            labeledCard(app.L(.spanRealTitle), app.L(.spanRealBody))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.L(.spanTranscript)).font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 0.39, green: 0.47, blue: 0.55))
                ForEach(Array(excerpts.enumerated()), id: \.offset) { _, excerpt in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(excerpt.role).font(.system(size: 10, design: .monospaced)).foregroundStyle(VColor.accent)
                        Text(excerpt.text).font(.system(size: 12))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func labeledCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10.5))
                .foregroundStyle(Color(red: 0.39, green: 0.47, blue: 0.55))
            Text(body).font(.system(size: 12)).padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
        }
    }
}
