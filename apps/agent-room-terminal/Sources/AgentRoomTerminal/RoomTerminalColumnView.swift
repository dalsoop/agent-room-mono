import SwiftUI
import AppKit
import AgentRoomTerminalCore

struct RoomTerminalColumnView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            switch model.viewMode {
            case .canvas:
                RoomCanvasView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .perspective:
                RoomPerspectiveView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .terminal:
                if let room = model.selectedNode {
                    RoomBriefingHeaderView(model: model, room: room)
                }
                terminalBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("room-terminal")
    }


    @ViewBuilder
    private func toolbarActions(iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            let hasSelection = model.selectedNode != nil
            let hasSession = model.selectedNode?.sessionID != nil

            Button(action: { Task { await model.openSessionForSelectedRoom() } }) {
                Label(model.L(.toolbarOpenSession), systemImage: "play.fill")
            }
            .disabled(!hasSelection || hasSession)
            .accessibilityIdentifier("toolbar-open-session")

            Button(action: { Task { await model.closeSessionForSelectedRoom() } }) {
                Label(model.L(.toolbarCloseSession), systemImage: "stop.fill")
            }
            .disabled(!hasSelection || !hasSession)
            .accessibilityIdentifier("toolbar-close-session")

            Button(action: { model.requestRoomAction(op: "handoff", roomID: model.selectedID ?? "") }) {
                Label(model.L(.toolbarHandoff), systemImage: "arrow.right.doc.on.clipboard")
            }
            .disabled(!hasSelection)
            .accessibilityIdentifier("toolbar-handoff")

            Button(action: { Task { await model.runVerdictForSelectedRoom() } }) {
                Label(model.L(.toolbarVerdict), systemImage: "checkmark.circle")
            }
            .disabled(!hasSelection)
            .accessibilityIdentifier("toolbar-verdict")

            Button(action: { model.openWorkFolderForSelectedRoom() }) {
                Label(model.L(.toolbarOpenFolder), systemImage: "folder")
            }
            .disabled(!hasSelection)
            .accessibilityIdentifier("toolbar-open-folder")

        }
        .modifier(ToolbarLabelFolding(iconOnly: iconOnly))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // 폭이 좁으면 라벨을 접고 아이콘만 남긴다(1200pt 창에서 "세션…"·"인수…" 로 잘리던 것).
            ViewThatFits(in: .horizontal) {
                toolbarActions(iconOnly: false)
                toolbarActions(iconOnly: true)
            }

            // 보기 모드 전환 (터미널 vs 캔버스 vs 관점)
            Picker("", selection: $model.viewMode) {
                Label(model.L(.canvasViewModeTerminal), systemImage: "terminal").tag(MainViewMode.terminal)
                Label(model.L(.canvasViewModeCanvas), systemImage: "square.grid.2x2").tag(MainViewMode.canvas)
                Label(model.L(.canvasViewModePerspective), systemImage: "scope").tag(MainViewMode.perspective)
            }
            .pickerStyle(.segmented)
            .frame(width: 255)
            .accessibilityIdentifier("toolbar-view-mode-picker")

            Spacer()

            if model.usingFixture {
                Text(model.L(.canvasExample))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.purple.opacity(0.18))
                    .clipShape(Capsule())
            }

            Button(model.L(.menuRefresh)) {
                Task { await model.refresh() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var terminalBody: some View {
        if let node = model.selectedNode {
            if node.sessionID != nil {
                activeTerminalView(for: node)
            } else {
                noSessionView(for: node)
            }
        } else {
            noSelectionView
        }
    }

    private func activeTerminalView(for node: RoomSummary) -> some View {
        TerminalContainerView(model: model, room: node)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noSessionView(for node: RoomSummary) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(model.L(.terminalNoSession))
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(model.L(.toolbarOpenSession)) {
                Task { await model.openSessionForSelectedRoom() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("empty-open-session")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(model.L(.detailEmpty))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// SwiftUI wrapper for hosting the terminal engine view.
struct TerminalContainerView: NSViewRepresentable {
    var model: AppModel
    var room: RoomSummary

    final class Coordinator {
        var currentRoomID: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        context.coordinator.currentRoomID = room.id
        model.attachTerminalEngine(for: room, in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.currentRoomID != room.id {
            context.coordinator.currentRoomID = room.id
            model.attachTerminalEngine(for: room, in: nsView)
        }
    }
}

/// 라벨 접기 — 좁으면 시스템 iconOnly 스타일(제목은 접근성 이름으로 남는다), 넓으면 제목+아이콘.
private struct ToolbarLabelFolding: ViewModifier {
    let iconOnly: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if iconOnly {
            content.labelStyle(.iconOnly)
        } else {
            content.labelStyle(.titleAndIcon)
        }
    }
}
