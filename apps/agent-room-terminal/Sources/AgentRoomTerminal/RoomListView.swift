import SwiftUI
import AgentRoomTerminalCore

struct RoomListView: View {
    @Bindable var model: AppModel
    @State private var selectedTenantFilter: String? = nil
    @State private var collapsedTenants: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerControls
            Divider()
            roomList
        }
        .accessibilityIdentifier("room-list")
    }

    private var availableTenants: [String] {
        let unique = Array(Set(model.groupedRooms.map(\.tenant))).sorted()
        return unique
    }

    private var displayedGroups: [(tenant: String, rooms: [RoomSummary])] {
        let all = model.groupedRooms
        if let selected = selectedTenantFilter {
            return all.filter { $0.tenant == selected }
        }
        return all
    }

    private var headerControls: some View {
        VStack(spacing: 8) {
            Picker("", selection: $model.listFilter) {
                Text(model.L(.filterActive)).tag(RoomListFilterMode.active)
                Text(model.L(.filterAll)).tag(RoomListFilterMode.all)
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(model.L(.searchPlaceholder), text: $model.searchQuery)
                    .textFieldStyle(.plain)
                if !model.searchQuery.isEmpty {
                    Button(action: { model.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            TenantFilterChipBar(
                tenants: availableTenants,
                selectedTenant: $selectedTenantFilter,
                allLabel: model.L(.canvasTenantFilterAll)
            )
        }
        .padding(10)
    }

    private var roomList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                let groups = displayedGroups
                if groups.isEmpty {
                    Text(model.L(.roomsEmpty))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(groups, id: \.tenant) { group in
                        Section {
                            if !collapsedTenants.contains(group.tenant) {
                                VStack(spacing: 4) {
                                    ForEach(group.rooms, id: \.id) { room in
                                        roomRow(room)
                                    }
                                }
                            }
                        } header: {
                            TenantAccordionHeader(
                                tenant: group.tenant,
                                count: group.rooms.count,
                                isCollapsed: collapsedTenants.contains(group.tenant),
                                onToggle: {
                                    if collapsedTenants.contains(group.tenant) {
                                        collapsedTenants.remove(group.tenant)
                                    } else {
                                        collapsedTenants.insert(group.tenant)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func roomRow(_ room: RoomSummary) -> some View {
        let isSelected = model.selectedID == room.id
        return Button(action: { model.selectRoom(id: room.id) }) {
            HStack(spacing: 8) {
                statusDot(for: room)

                VStack(alignment: .leading, spacing: 2) {
                    Text(RoomListFilter.displayName(for: room))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, alignment: .leading)
                        .foregroundStyle(isSelected ? .white : .primary)

                    HStack(spacing: 4) {
                        toolIcon(for: room, isSelected: isSelected)
                        Text(budgetText(for: room))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        budgetBadge(for: room, isSelected: isSelected)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                resultBadge(for: room, isSelected: isSelected)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            model.loadResultBadgeIfNeeded(for: room.id)
        }
        .accessibilityIdentifier("room-row-\(room.id)")
    }

    private func statusDot(for room: RoomSummary) -> some View {
        let dot = model.statusDot(for: room)
        let color: Color = switch dot {
        case .executing: .green
        case .waitingInput: .orange
        case .completed: .gray
        case .error: .red
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func detectedTool(for room: RoomSummary) -> AgentRoomTool? {
        for occupant in room.occupants {
            if let tool = RoomToolDetector.parseToolFromHandle(occupant.handle) {
                return tool
            }
        }
        let lower = (room.title + " " + room.id).lowercased()
        for candidate in AgentRoomTool.allCases {
            if lower.contains(candidate.rawValue) {
                return candidate
            }
        }
        return nil
    }

    private func toolVisual(for tool: AgentRoomTool?) -> (icon: String, color: Color) {
        guard let tool else {
            return ("terminal", .secondary)
        }
        switch tool {
        case .claude:
            return ("bubble.left.and.text.bubble.right.fill", .orange)
        case .codex:
            return ("chevron.left.forwardslash.chevron.right", .green)
        case .grok:
            return ("bolt.fill", .red)
        case .agy:
            return ("triangle.fill", .purple)
        }
    }

    private func toolIcon(for room: RoomSummary, isSelected: Bool) -> some View {
        let (icon, color) = toolVisual(for: detectedTool(for: room))
        return Image(systemName: icon)
            .font(.system(size: 10))
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : color)
    }

    @ViewBuilder
    private func resultBadge(for room: RoomSummary, isSelected: Bool) -> some View {
        let badge = model.resultBadge(for: room.id)
        if badge != .none {
            let badgeColor: Color = switch badge {
            case .done: .green
            case .partial: .orange
            case .blocked: .red
            case .none: .clear
            }
            let badgeText: String = switch badge {
            case .done: model.L(.resultDone)
            case .partial: model.L(.resultPartial)
            case .blocked: model.L(.resultBlocked)
            case .none: ""
            }
            Text(badgeText)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(badgeColor.opacity(isSelected ? 0.4 : 0.2))
                .foregroundStyle(isSelected ? .white : badgeColor)
                .clipShape(Capsule())
        }
    }

    private func budgetText(for room: RoomSummary) -> String {
        RoomUsageText.format(usage: room.budget, unknownText: model.L(.budgetUnknown))
    }

    @ViewBuilder
    private func budgetBadge(for room: RoomSummary, isSelected: Bool) -> some View {
        let budget = room.budget
        if !budget.isUnknown, let fraction = budget.fraction {
            if fraction >= 1.0 {
                Text(model.L(.budgetOver))
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(isSelected ? 0.5 : 0.25))
                    .foregroundStyle(isSelected ? .white : .red)
                    .clipShape(Capsule())
            } else if fraction >= 0.8 {
                Text(model.L(.budgetHandoffDue))
                    .font(.system(size: 8, weight: .medium))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(isSelected ? 0.5 : 0.25))
                    .foregroundStyle(isSelected ? .white : .orange)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - TenantAccordionHeader
struct TenantAccordionHeader: View {
    let tenant: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    private var symbol: String {
        let lower = tenant.lowercased()
        if lower == "personal" { return "person.crop.circle.fill" }
        if lower == "gujo" { return "building.2.fill" }
        if lower == "system" { return "gearshape.2.fill" }
        return "folder.fill"
    }

    private var color: Color {
        let lower = tenant.lowercased()
        if lower == "personal" { return .indigo }
        if lower == "gujo" { return .blue }
        if lower == "system" { return .secondary }
        return .teal
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(color)

                Text(tenant.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(verbatim: "\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tenant-accordion-\(tenant)")
    }
}

// MARK: - TenantFilterChipBar
struct TenantFilterChipBar: View {
    let tenants: [String]
    @Binding var selectedTenant: String?
    let allLabel: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: allLabel, isSelected: selectedTenant == nil) {
                    selectedTenant = nil
                }
                ForEach(tenants, id: \.self) { tenant in
                    chip(title: tenant.capitalized, isSelected: selectedTenant == tenant) {
                        selectedTenant = (selectedTenant == tenant) ? nil : tenant
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("tenant-filter-chip-bar")
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tenant-chip-\(title.lowercased())")
    }
}
