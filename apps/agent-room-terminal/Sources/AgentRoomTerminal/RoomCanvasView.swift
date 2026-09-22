import SwiftUI
import AppKit
import AgentRoomTerminalCore

struct RoomCanvasView: View {
    @Bindable var model: AppModel

    @State private var offset: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var scale: Double = 1.0
    @State private var lastViewportSize: CGSize = .zero

    private var availableTenants: [String] {
        let rawTenants = model.nodes.map { RoomCanvasFilter.tenant(for: $0) }
        let unique = Array(Set(rawTenants)).filter { !$0.isEmpty && $0 != "all" }.sorted()
        return ["all"] + unique
    }

    private var displayRooms: [RoomSummary] {
        RoomCanvasFilter.filter(
            rooms: model.nodes,
            tenantFilter: model.canvasTenantFilter,
            hideInactiveRooms: model.canvasHideInactive,
            searchQuery: model.searchQuery
        )
    }

    private var placedCards: [CanvasPlacedCard] {
        RoomCanvasLayout.layout(rooms: displayRooms)
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            Divider()
            canvasBody
        }
        .accessibilityIdentifier("room-canvas-view")
    }

    private var tenantPicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            Picker("", selection: $model.canvasTenantFilter) {
                Text(model.L(.canvasTenantFilterAll)).tag("all")
                ForEach(availableTenants.filter { $0 != "all" }, id: \.self) { tenant in
                    Text(tenant).tag(tenant)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120)
            .accessibilityIdentifier("canvas-tenant-picker")
        }
    }

    private var inactiveToggle: some View {
        Toggle(isOn: $model.canvasHideInactive) {
            Text(model.L(.canvasHideInactive))
                .font(.caption)
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("canvas-hide-inactive-toggle")
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button(action: { zoom(by: 0.8) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)

            Text(verbatim: "\(Int((scale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = 1.0
                    }
                }

            Button(action: { zoom(by: 1.25) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var fitButton: some View {
        Button(action: { fitToView(animated: true) }) {
            Label(model.L(.canvasFitToScreen), systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("canvas-fit-button")
    }

    private var controlsBar: some View {
        HStack(spacing: 12) {
            tenantPicker
            inactiveToggle
            Spacer()
            fitButton
            zoomControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var canvasBody: some View {
        GeometryReader { proxy in
            ZStack {
                canvasBackground
                if placedCards.isEmpty {
                    emptyCanvasView
                } else {
                    cardsLayer
                }
            }
            .clipped()
            .onAppear {
                lastViewportSize = proxy.size
                fitToView(animated: false)
            }
            .onChange(of: proxy.size) { _, newSize in
                lastViewportSize = newSize
            }
            .onChange(of: model.canvasTenantFilter) { _, _ in
                fitToView(animated: true)
            }
            .onChange(of: model.canvasHideInactive) { _, _ in
                fitToView(animated: true)
            }
        }
    }

    private var canvasBackground: some View {
        Color(nsColor: .underPageBackgroundColor)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        offset = CGPoint(
                            x: offset.x + value.translation.width,
                            y: offset.y + value.translation.height
                        )
                        dragOffset = .zero
                    }
            )
            .onTapGesture {
                model.selectedID = nil
            }
    }

    private var emptyCanvasView: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(model.L(.canvasEmpty))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var cardsLayer: some View {
        let effectiveOffsetX = offset.x + dragOffset.width
        let effectiveOffsetY = offset.y + dragOffset.height

        return ForEach(placedCards) { card in
            RoomCanvasCardView(
                room: card.room,
                model: model,
                isSelected: model.selectedID == card.room.id
            )
            .frame(width: card.size.width, height: card.size.height)
            .position(
                x: card.position.x * scale + effectiveOffsetX,
                y: card.position.y * scale + effectiveOffsetY
            )
            .scaleEffect(scale)
        }
    }

    private func zoom(by factor: Double) {
        withAnimation(.easeInOut(duration: 0.15)) {
            scale = min(2.5, max(0.2, scale * factor))
        }
    }

    private func fitToView(animated: Bool) {
        let viewport = lastViewportSize
        guard viewport.width > 0, viewport.height > 0 else { return }

        let transform = RoomCanvasFitCalculator.calculateFit(
            cards: placedCards,
            viewport: viewport,
            padding: 40
        )

        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = transform.scale
                offset = transform.offset
            }
        } else {
            scale = transform.scale
            offset = transform.offset
        }
    }
}

/// 캔버스에 표시되는 개별 방 카드 뷰.
struct RoomCanvasCardView: View {
    let room: RoomSummary
    let model: AppModel
    let isSelected: Bool

    private var isInactive: Bool {
        RoomCanvasFilter.isInactive(room: room)
    }

    var body: some View {
        Button(action: { model.selectRoom(id: room.id) }) {
            cardContent
        }
        .buttonStyle(.plain)
        .roomContextMenu(room: room, model: model)
        .accessibilityIdentifier("canvas-card-\(room.id)")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardHeader
            Divider().opacity(isSelected ? 0.4 : 1.0)
            occupantAndPidRow
            usageProgressRow
            cardFooter
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(isSelected ? 0.25 : 0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(cardBorder)
        .opacity(isInactive ? 0.65 : 1.0)
    }

    private var cardBorder: some View {
        let strokeColor: Color
        if isSelected {
            strokeColor = Color.white.opacity(0.5)
        } else if isInactive {
            strokeColor = Color.gray.opacity(0.3)
        } else {
            strokeColor = Color(nsColor: .separatorColor)
        }
        return RoundedRectangle(cornerRadius: 8)
            .stroke(strokeColor, lineWidth: isSelected ? 2 : 1)
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            statusDot
            Text(RoomListFilter.displayName(for: room))
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            Spacer(minLength: 0)

            Text(RoomCanvasFilter.tenant(for: room))
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tenantBadgeBackground)
                .clipShape(Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
    }

    private var tenantBadgeBackground: Color {
        if isSelected {
            return Color.white.opacity(0.25)
        }
        return Color(nsColor: .tertiaryLabelColor).opacity(0.15)
    }

    private enum DeskStatus {
        case occupied(handle: String, pid: Int?)
        case vacant(bottleCount: Int)
        case unseated(sessionID: String)
    }

    private var deskStatus: DeskStatus {
        if let occ = room.occupants.first?.handle, !occ.isEmpty {
            return .occupied(handle: occ, pid: room.pid)
        }
        if let pid = room.pid {
            let handle = room.sessionID.map { String($0.prefix(8)) } ?? "PID:\(pid)"
            return .occupied(handle: handle, pid: pid)
        }
        if let sessionID = room.sessionID, !sessionID.isEmpty {
            if room.occupants.isEmpty && room.status.phase == .open {
                return .unseated(sessionID: sessionID)
            }
            return .occupied(handle: String(sessionID.prefix(8)), pid: nil)
        }
        return .vacant(bottleCount: room.bottles.count)
    }

    @ViewBuilder
    private func occupiedDeskRow(handle: String, pid: Int?) -> some View {
        Image(systemName: "chair.lounge.fill")
            .font(.system(size: 9))
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.green)
        Text(handle)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .frame(minWidth: 0, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)

        if let pid = pid {
            Text(verbatim: "PID:\(pid)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(isSelected ? Color.green.opacity(0.4) : Color.green.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityIdentifier("card-pid-\(room.id)")
        }
    }

    @ViewBuilder
    private func vacantDeskRow(bottleCount: Int) -> some View {
        Image(systemName: "chair.lounge")
            .font(.system(size: 9))
            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
        Text(String(localized: "Desk Vacant"))
            .font(.system(size: 11))
            .lineLimit(1)
            .frame(minWidth: 0, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

        if bottleCount > 0 {
            HStack(spacing: 2) {
                Text(verbatim: "🍾")
                    .font(.system(size: 8))
                Text(verbatim: "\(bottleCount)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(isSelected ? Color.orange.opacity(0.4) : Color.orange.opacity(0.15))
            .foregroundStyle(isSelected ? Color.white : Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder
    private func unseatedDeskRow(sessionID: String) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9))
            .foregroundStyle(isSelected ? Color.white : Color.orange)
        Text(String(localized: "Unseated"))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSelected ? Color.white : Color.orange)
        Text(verbatim: String(sessionID.prefix(8)))
            .font(.system(size: 9, design: .monospaced))
            .frame(minWidth: 0, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
    }

    private var occupantAndPidRow: some View {
        HStack(spacing: 5) {
            switch deskStatus {
            case .occupied(let handle, let pid):
                occupiedDeskRow(handle: handle, pid: pid)
            case .vacant(let bottleCount):
                vacantDeskRow(bottleCount: bottleCount)
            case .unseated(let sessionID):
                unseatedDeskRow(sessionID: sessionID)
            }
        }
    }

    private var usageProgressRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                Text(budgetText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                Spacer()
                if let fraction = room.budget.fraction {
                    Text(verbatim: "\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
            }

            if let fraction = room.budget.fraction {
                GeometryReader { gaugeProxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? Color.white.opacity(0.2) : Color(nsColor: .separatorColor))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fraction > 0.8 ? Color.red : (isSelected ? Color.white : Color.accentColor))
                            .frame(width: gaugeProxy.size.width * CGFloat(fraction))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var cardFooter: some View {
        HStack {
            Text(room.status.phase.rawValue)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            Spacer()
            Text(room.wallPreset)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.7))
        }
    }

    private var statusDot: some View {
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

    private var budgetText: String {
        if let used = room.budget.used {
            return "\(used)/\(room.budget.handoffAt)"
        }
        return model.L(.budgetUnknown)
    }
}
