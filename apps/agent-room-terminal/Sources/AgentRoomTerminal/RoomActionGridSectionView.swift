import AgentRoomTerminalCore
import SwiftUI

/// Actions.dc.html 기반 3열 빠른 행동 명령 격자 (Action Grid).
/// 방 상태(현임 재실 vs 공석)에 따라 Core CLI와 1:1 매핑된 실질적 행동 버튼 제공.
struct RoomActionGridSectionView: View {
    let model: AppModel
    let node: RoomSummary

    private var isOccupied: Bool {
        if case .loaded(let feed) = model.roomSurface.seatChains,
           let chain = feed.chains[node.id] {
            return !chain.current.isEmpty
        }
        return !node.occupants.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Quick Actions"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                if isOccupied {
                    occupiedGrid
                } else {
                    vacantGrid
                }
            }
        }
        .accessibilityIdentifier("room-action-grid")
    }

    private var occupiedGrid: some View {
        Group {
            GridRow {
                actionButton(
                    title: String(localized: "Open Terminal"),
                    shortcut: "⌘↩",
                    icon: "terminal",
                    isPrimary: true
                ) {
                    model.viewMode = .terminal
                }

                actionButton(
                    title: String(localized: "Handoff (Bottle)"),
                    shortcut: "⌘⇧N",
                    icon: "arrow.right.circle",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "handoff", roomID: node.id)
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Run Verdict"),
                    shortcut: "⌘R",
                    icon: "play.circle",
                    isPrimary: false
                ) {
                    Task { await model.runVerdictForSelectedRoom() }
                }

                actionButton(
                    title: String(localized: "Attach Walls"),
                    shortcut: "",
                    icon: "shield",
                    isPrimary: false
                ) {
                    Task { await model.attachWalls(for: node) }
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Checkpoints"),
                    shortcut: "",
                    icon: "clock.arrow.circlepath",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "checkpoint", roomID: node.id)
                }

                actionButton(
                    title: String(localized: "Profile Lock"),
                    shortcut: "",
                    icon: "lock.shield",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "profile-lock", roomID: node.id)
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Runs"),
                    shortcut: "",
                    icon: "doc.text.magnifyingglass",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "runs", roomID: node.id)
                }

                actionButton(
                    title: String(localized: "Precompute"),
                    shortcut: "",
                    icon: "brain.head.profile",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "precompute", roomID: node.id)
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Cognitive Delta"),
                    shortcut: "",
                    icon: "chart.line.uptrend.xyaxis",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "delta", roomID: node.id)
                }

                actionButton(
                    title: String(localized: "Synapses"),
                    shortcut: "",
                    icon: "network",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "synapses", roomID: node.id)
                }
            }
        }
    }

    private var vacantGrid: some View {
        Group {
            GridRow {
                actionButton(
                    title: String(localized: "Seat Successor"),
                    shortcut: "⌘⇧S",
                    icon: "chair.lounge",
                    isPrimary: true
                ) {
                    Task { await model.takeSeat(for: node) }
                }

                actionButton(
                    title: String(localized: "Resume Session"),
                    shortcut: "⌘↩",
                    icon: "play.fill",
                    isPrimary: false
                ) {
                    Task { await model.openSessionForSelectedRoom() }
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Work Folder"),
                    shortcut: "",
                    icon: "folder",
                    isPrimary: false
                ) {
                    model.openWorkFolderForSelectedRoom()
                }

                actionButton(
                    title: String(localized: "Simulate Verdict"),
                    shortcut: "⌘R",
                    icon: "play.circle",
                    isPrimary: false
                ) {
                    Task { await model.runVerdictForSelectedRoom() }
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Checkpoints"),
                    shortcut: "",
                    icon: "clock.arrow.circlepath",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "checkpoint", roomID: node.id)
                }

                actionButton(
                    title: String(localized: "Profile Lock"),
                    shortcut: "",
                    icon: "lock.shield",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "profile-lock", roomID: node.id)
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Runs"),
                    shortcut: "",
                    icon: "doc.text.magnifyingglass",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "runs", roomID: node.id)
                }

                actionButton(
                    title: String(localized: "Precompute"),
                    shortcut: "",
                    icon: "brain.head.profile",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "precompute", roomID: node.id)
                }
            }

            GridRow {
                actionButton(
                    title: String(localized: "Cognitive Delta"),
                    shortcut: "",
                    icon: "chart.line.uptrend.xyaxis",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "delta", roomID: node.id)
                }

                actionButton(
                    title: String(localized: "Synapses"),
                    shortcut: "",
                    icon: "network",
                    isPrimary: false
                ) {
                    model.requestRoomAction(op: "synapses", roomID: node.id)
                }
            }
        }
    }

    private func actionButton(
        title: String,
        shortcut: String,
        icon: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: isPrimary ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(minWidth: 0)
                Spacer(minLength: 2)
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(isPrimary ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isPrimary ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isPrimary ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isPrimary ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
