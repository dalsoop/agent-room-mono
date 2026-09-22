import AgentRoomTerminalCore
import SwiftUI

struct RoomDetailView: View {
    var model: AppModel
    var node: RoomSummary?
    @State private var selectedTab: RoomDetailTab = .seat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let node {
                    header(node)
                    RoomActionGridSectionView(model: model, node: node)
                    tabBar
                    tabContent(node)
                } else {
                    Text(model.L(.detailEmpty))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .accessibilityIdentifier("room-detail")
    }

    private func header(_ node: RoomSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(node.title).font(.headline)
                if node.isExample {
                    Text(model.L(.canvasExample))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.2))
                        .clipShape(Capsule())
                }
                statusBadge(node)
            }
            Text(String(localized: "Room \(String(node.id.prefix(8))) · Seat Chain"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ node: RoomSummary) -> some View {
        Text(node.status.rawValue)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(RoomDetailTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Text(tab.title)
                            .font(.system(size: 12, weight: selectedTab == tab ? .bold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private func tabContent(_ node: RoomSummary) -> some View {
        switch selectedTab {
        case .room:
            roomTabContent(node)
        case .seat:
            seatTabContent(node)
        case .permissions:
            permissionsTabContent(node)
        case .context:
            contextTabContent(node)
        case .events:
            eventsTabContent(node)
        }
    }

    @ViewBuilder
    private func roomTabContent(_ node: RoomSummary) -> some View {
        taskSection(node)
        verdictSection(node)
        learnedHabitsSection(node)
        RoomResultSectionView(
            model: model,
            node: node,
            roomFolderResolver: RoomDetailHelper.roomFolder
        )
    }

    @ViewBuilder
    private func seatTabContent(_ node: RoomSummary) -> some View {
        RoomSeatTabDetailView(model: model, node: node)
        RoomSeatChainSectionView(model: model, node: node)
        handoffNotesSection(node)
    }

    @ViewBuilder
    private func permissionsTabContent(_ node: RoomSummary) -> some View {
        RoomWallPresetSection(model: model, node: node)
        credentialSeedSection(node)
        writePathsSection(node)
        networkSection(node)
        excludedToolsSection(node)
    }

    @ViewBuilder
    private func contextTabContent(_ node: RoomSummary) -> some View {
        BudgetBarView(
            usage: node.budget,
            title: model.L(.detailBudget),
            unknownText: model.L(.budgetUnknown)
        )
        let occupant = node.occupants.first?.handle ?? ""
        if !occupant.isEmpty {
            RoomDetailItemView(title: model.L(.detailOccupant), bodyText: occupant)
        }
    }

    @ViewBuilder
    private func eventsTabContent(_ node: RoomSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Event History"))
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "No recent state transition events recorded"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func credentialSeedSection(_ node: RoomSummary) -> some View {
        if node.kind.hostsTerminal, let roomURL = RoomDetailHelper.roomFolder(for: node.id) {
            CredentialSeedStatusView(roomURL: roomURL, occupants: node.occupants, model: model)
        }
    }

    @ViewBuilder
    private func taskSection(_ node: RoomSummary) -> some View {
        let task = RoomDetailHelper.resolveTask(for: node)
        if !task.isEmpty {
            RoomDetailItemView(title: model.L(.detailTask), bodyText: task)
        }
    }

    @ViewBuilder
    private func verdictSection(_ node: RoomSummary) -> some View {
        let verdict = RoomDetailHelper.resolveVerdict(for: node)
        if !verdict.isEmpty {
            RoomDetailItemView(title: model.L(.detailVerdict), bodyText: verdict)
        }
    }

    @ViewBuilder
    private func writePathsSection(_ node: RoomSummary) -> some View {
        let paths = RoomDetailHelper.resolveWritePaths(for: node)
        if !paths.isEmpty {
            RoomDetailItemView(title: model.L(.detailWritePaths), bodyText: paths.joined(separator: "\n"))
        }
    }

    @ViewBuilder
    private func networkSection(_ node: RoomSummary) -> some View {
        if let network = RoomDetailHelper.resolveNetwork(for: node, model: model) {
            RoomDetailItemView(title: model.L(.detailNetwork), bodyText: network)
        }
    }

    @ViewBuilder
    private func handoffNotesSection(_ node: RoomSummary) -> some View {
        let notes = RoomDetailHelper.resolveHandoffNotes(for: node)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.L(.detailBottles))
                    .font(.subheadline.weight(.semibold))
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    @ViewBuilder
    private func learnedHabitsSection(_ node: RoomSummary) -> some View {
        let habitText = node.habitIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !habitText.isEmpty && habitText != "습관 없음" && habitText != "(없음)" {
            RoomDetailItemView(title: model.L(.detailHabits), bodyText: habitText)
        }
    }

    @ViewBuilder
    private func excludedToolsSection(_ node: RoomSummary) -> some View {
        let rows = model.exclusionLines(for: node)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.L(.detailExcluded)).font(.subheadline.weight(.semibold))
                ForEach(rows, id: \.cli) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.cli)
                            .font(.system(.body, design: .monospaced))
                        if !row.reason.isEmpty {
                            Text(row.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("excluded-tool-\(row.cli)")
                }
            }
        }
    }
}

private struct RoomWallPresetSection: View {
    var model: AppModel
    var node: RoomSummary

    var body: some View {
        switch node.wallPreset.isEmpty {
        case true:
            EmptyView()
        case false:
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.L(.detailWallPreset)).font(.subheadline.weight(.semibold))
                Text(presetText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button(model.L(.detailAttachWalls)) {
                Task { await model.attachWalls(for: node) }
            }
            .accessibilityIdentifier("room-attach-walls")
            badge
        }
    }

    private var presetText: String {
        switch node.wallPreset {
        case "readOnly": model.L(.presetReadOnly)
        case "toolbelt": model.L(.presetToolbelt)
        case "open": model.L(.presetOpen)
        default: node.wallPreset
        }
    }

    @ViewBuilder
    private var badge: some View {
        let text = model.roomSurface.wallEnforcementByRoom[node.id] ?? ""
        switch text.isEmpty {
        case true:
            EmptyView()
        case false:
            Text(text)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .clipShape(Capsule())
                .accessibilityIdentifier("room-attach-enforcement")
        }
    }
}

private struct CredentialSeedStatusView: View {
    let roomURL: URL
    let occupants: [RoomOccupant]
    let model: AppModel

    var body: some View {
        let readiness = ToolAuthReadinessPolicy.evaluate(roomURL: roomURL, occupants: occupants)
        switch readiness {
        case .ready(let tool):
            Label(statusText(for: tool, ready: true), systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.green)
        case .unready(let tool, _):
            Label(statusText(for: tool, ready: false), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .notApplicable:
            EmptyView()
        }
    }

    private func statusText(for tool: AgentRoomTool, ready: Bool) -> String {
        if tool == .claude {
            return ready ? model.L(.detailCredentialSeeded) : model.L(.detailCredentialUnseeded)
        }
        return ready ? "\(tool.displayName) 준비됨" : "\(tool.displayName) 미준비"
    }
}
