import AgentRoomTerminalCore
import SwiftUI

/// InspectorSeatHandoff.dc.html 정본 시안에 따른 [좌석] 탭 상세 뷰.
/// 전임 1 → 후임(simulating/vacant) 사슬, 인수인계 팩 카드, 스텝 검증 및 확정 액션 포함.
struct RoomSeatTabDetailView: View {
    let model: AppModel
    let node: RoomSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chainHeader
            predecessorSection
            arrowIndicator
            successorSection
            handoffPackSection
            bottomActionBar
        }
    }

    private var chain: RoomGraphSeatChain? {
        guard case .loaded(let feed) = model.roomSurface.seatChains else { return nil }
        return feed.chains[node.id]
    }

    private var chainHeader: some View {
        HStack {
            Text(String(localized: "Seat Chain · Predecessor 1 → Successor"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var predecessorSection: some View {
        let occupant = chain?.predecessor ?? node.occupants.first(where: { !$0.isSuccessor })?.handle ?? node.occupants.first?.handle
        if let occupant, !occupant.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Predecessor"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(localized: "Survives until sim pass"))
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(occupant)
                    .font(.system(size: 13, weight: .semibold))

                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        Text(String(localized: "Duration"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(node.sessionID != nil ? String(localized: "Active session") : "-")
                            .font(.system(size: 11))
                    }
                    GridRow {
                        Text(String(localized: "Bottle"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(verbatim: bottleText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Predecessor"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(String(localized: "No predecessor"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
    }

    private var bottleText: String {
        if let first = node.bottles.first {
            return "\(first.id) · ↓ record"
        }
        return "-"
    }

    private var arrowIndicator: some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.tint)
            Spacer()
        }
    }

    @ViewBuilder
    private var successorSection: some View {
        let isOccupied = !(chain?.current.isEmpty ?? true) || node.occupants.contains { $0.isSuccessor }
        let successorName = (chain?.current.isEmpty == false ? chain?.current : nil)
            ?? node.occupants.first(where: { $0.isSuccessor })?.handle
            ?? (isOccupied ? node.occupants.first?.handle : nil)
            ?? String(localized: "Waiting for successor")

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Successor"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isOccupied ? "occupied" : "simulating")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isOccupied ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundStyle(isOccupied ? Color.green : Color.orange)
                    .clipShape(Capsule())
            }

            Text(successorName)
                .font(.system(size: 13.5, weight: .semibold))

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text(String(localized: "Pane"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: node.sessionID ?? "-")
                        .font(.system(size: 11, design: .monospaced))
                }
                GridRow {
                    Text(String(localized: "Account"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: node.occupants.first?.handle ?? "-")
                        .font(.system(size: 11, design: .monospaced))
                }
                GridRow {
                    Text(String(localized: "Walls"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(node.wallPreset.isEmpty ? "-" : node.wallPreset)
                        .font(.system(size: 11))
                }
            }

            stepsView
        }
        .padding(10)
        .background(Color.orange.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.4), lineWidth: 1.5))
    }

    @ViewBuilder
    private var stepsView: some View {
        if !node.bottles.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(node.bottles, id: \.id) { bottle in
                    stepRow(status: .done, text: "bottle · \(bottle.id)")
                }
                if let successor = node.occupants.first(where: { $0.isSuccessor }) {
                    stepRow(status: .done, text: "successor · \(successor.handle)")
                }
            }
            .padding(.top, 4)
        } else {
            Text(String(localized: "No pending successor steps"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private enum StepStatus { case done, inProgress, pending }

    private func stepRow(status: StepStatus, text: String) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            case .inProgress:
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var handoffPackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Handoff Pack (agent-handoff)"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if !node.bottles.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text(String(localized: "Status"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Available · \(node.bottles.count) bottle(s)"))
                            .font(.system(size: 11))
                    }
                    GridRow {
                        Text(String(localized: "Latest"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(node.bottles.first?.id ?? "-")
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(String(localized: "No handoff pack available"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                Task { await model.takeSeat(for: node) }
            }) {
                Text(String(localized: "Confirm Successor"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(action: {
                model.requestRoomAction(op: "handoff", roomID: node.id)
            }) {
                Text(String(localized: "Edit Bottle"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 6)
    }
}
