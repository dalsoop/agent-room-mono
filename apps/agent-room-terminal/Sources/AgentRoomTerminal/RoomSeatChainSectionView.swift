import AgentRoomTerminalCore
import SwiftUI

/// 방 상세 "좌석 사슬" 카드. room-graph.json(파일 감시) 의 전임 · 현임 · 후임을 보이고,
/// 파일이 낡았거나 못 읽으면 그 사실을 숨기지 않는다.
struct RoomSeatChainSectionView: View {
    let model: AppModel
    let node: RoomSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.L(.detailSeatChain)).font(.subheadline.weight(.semibold))
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.roomSurface.seatChains {
        case .notLoaded:
            secondary(model.L(.detailSeatChainNone))
        case .failed(let reason):
            secondary("\(model.L(.detailSeatChainUnavailable)) · \(reason)")
        case .loaded(let feed):
            loaded(feed)
        }
    }

    @ViewBuilder
    private func loaded(_ feed: RoomGraphSeatChainFeed) -> some View {
        let chain = feed.chains[node.id]
        VStack(alignment: .leading, spacing: 6) {
            seatChainHStack(chain: chain)
            if feed.stale {
                secondary("\(model.L(.detailSeatChainStale)) · \(feed.generatedAt)")
            }
        }
    }

    @ViewBuilder
    private func predecessorSegment(predecessor: String?) -> some View {
        if let predecessor, !predecessor.isEmpty {
            predecessorCard(occupant: predecessor)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func currentSegment(chain: RoomGraphSeatChain?) -> some View {
        if let chain, !chain.current.isEmpty {
            currentSeatCard(occupant: chain.current, session: chain.session)
        } else {
            vacantSeatCard
        }
    }

    @ViewBuilder
    private func successorSegment(successor: String?) -> some View {
        if let successor, !successor.isEmpty {
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            successorCard(occupant: successor)
        }
    }

    @ViewBuilder
    private func seatChainHStack(chain: RoomGraphSeatChain?) -> some View {
        HStack(spacing: 8) {
            predecessorSegment(predecessor: chain?.predecessor)
            currentSegment(chain: chain)
            successorSegment(successor: chain?.successor)
        }
    }

    @ViewBuilder
    private func predecessorCard(occupant: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                Text(String(localized: "Predecessor (Log)"))
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            Text(verbatim: occupant)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            Text(String(localized: "🍾 Handoff Bottle"))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(minWidth: 110, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private func currentSeatCard(occupant: String, session: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                Text(String(localized: "Current (Working)"))
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tint)

            Text(verbatim: occupant)
                .font(.system(.caption, design: .monospaced))
                .bold()
                .lineLimit(1)

            if !session.isEmpty {
                Text(verbatim: "ID: \(session.prefix(8))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(minWidth: 120, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1.5))
    }

    @ViewBuilder
    private var vacantSeatCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chair.lounge")
                Text(String(localized: "Current (Vacant)"))
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            Text(String(localized: "Desk is waiting"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(String(localized: "Take Seat")) {
                model.selectRoom(id: node.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(8)
        .frame(minWidth: 120, alignment: .leading)
        .background(Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
    }

    @ViewBuilder
    private func successorCard(occupant: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.right")
                Text(String(localized: "Successor"))
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.orange)

            Text(verbatim: occupant)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
        }
        .padding(8)
        .frame(minWidth: 100, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.4), lineWidth: 1))
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}
