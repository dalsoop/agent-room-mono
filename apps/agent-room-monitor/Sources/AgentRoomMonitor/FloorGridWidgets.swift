import AgentRoomMonitorCore
import SwiftUI

/// 경영 시뮬 문법 에이전트 Pawn 뱃지 및 토큰 링 (위키 정본 913d45ec 전수 32항 준수).
@MainActor
struct FloorPawnView: View {
    let name: String
    let tokens: Int
    let maxTokens: Int
    let isOccupied: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isOccupied {
                pawnAvatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(minWidth: 0)
                    tokenBar
                }
            } else {
                Text(name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 0)
            }
        }
    }

    private var pawnAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 18, height: 18)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var tokenBar: some View {
        let ceiling = max(maxTokens > 0 ? maxTokens : 100_000, 1)
        let ratio = min(max(Double(tokens) / Double(ceiling), 0), 1.0)
        let barColor: Color = ratio >= 0.9 ? VColor.bad : (ratio >= 0.7 ? VColor.gate : VColor.exec)

        return HStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(barColor).frame(width: geo.size.width * ratio)
                }
            }
            .frame(width: 38, height: 3)

            if tokens > 0 {
                let formatted = String(localized: "\(tokens / 1000)k")
                Text(formatted)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 방 OS 트윈 뱃지 (상태 점 + 방 명칭 + 볼트/블루프린트 캡슐).
@MainActor
struct FloorRoomCellView: View {
    let name: String
    let state: VState
    let blueprint: String
    let hasVault: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 6, height: 6)

            Text(name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(2)
                .frame(minWidth: 0)

            if hasVault {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(VColor.accent)
                    .help(String(localized: "Vault Active"))
            }

            if !blueprint.isEmpty {
                Text(blueprint)
                    .font(.system(size: 9, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stateColor(_ st: VState) -> Color {
        switch st {
        case .exec: return VColor.exec
        case .block: return VColor.bad
        case .gate: return VColor.gate
        case .done: return Color.gray
        case .sleep: return Color.blue
        case .queue: return Color.orange
        case .neutral: return Color.secondary
        }
    }
}

/// 테넌트 건물 뱃지 (빌딩 아이콘 + 테넌트 표시명).
@MainActor
struct FloorTenantCellView: View {
    let displayName: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "building.2.crop.rectangle")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.accentColor.opacity(0.8))
            Text(displayName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(minWidth: 0)
        }
    }
}

/// 상단 테넌트 건물 거시 HUD 바 (117개 방 조망).
@MainActor
struct FloorBuildingMacroHUD: View {
    let totalTenants: Int
    let totalRooms: Int
    let activeOccupants: Int
    let riskRooms: Int

    var body: some View {
        HStack(spacing: 16) {
            statItem(label: String(localized: "Buildings", defaultValue: "Buildings"), value: "\(totalTenants)", icon: "building.2", color: Color.primary)
            statItem(label: String(localized: "Rooms", defaultValue: "Rooms"), value: "\(totalRooms)", icon: "door.left.hand.open", color: Color.primary)
            statItem(label: String(localized: "Active", defaultValue: "Active"), value: "\(activeOccupants)", icon: "person.wave.2.fill", color: VColor.exec)
            if riskRooms > 0 {
                statItem(label: String(localized: "Isolation Risk", defaultValue: "Isolation Risk"), value: "\(riskRooms)", icon: "exclamationmark.triangle.fill", color: VColor.bad)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .overlay(alignment: .bottom) { Divider().opacity(0.2) }
    }

    private func statItem(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// 테넌트 건물 계층(Building Hierarchy) 가로 스택 바.
@MainActor
struct FloorBuildingHierarchyBar: View {
    let board: BoardModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(board.buildingSummaries) { summary in
                    FloorBuildingBarItem(summary: summary, board: board)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(Color.black.opacity(0.25))
        .overlay(alignment: .bottom) { Divider().opacity(0.15) }
    }
}

/// 개별 테넌트 건물 층계 아이템.
@MainActor
struct FloorBuildingBarItem: View {
    let summary: BoardModel.TenantBuildingSummary
    let board: BoardModel

    private var isSelected: Bool {
        if summary.isAll {
            return board.selectedTenantID == nil
        }
        return board.selectedTenantID == summary.id
    }

    var body: some View {
        Button {
            board.selectTenant(summary.isAll ? nil : summary.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: summary.isAll ? "globe.americas.fill" : "building.2.crop.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? VColor.accent : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(summary.displayName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)

                        if summary.isCurrent {
                            Circle()
                                .fill(VColor.exec)
                                .frame(width: 4.5, height: 4.5)
                                .help(String(localized: "Current Tenant", defaultValue: "Current Tenant"))
                        }
                    }

                    HStack(spacing: 5) {
                        Text(verbatim: "\(summary.totalRooms) \(String(localized: "rooms", defaultValue: "rooms"))")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if summary.activeOccupants > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 7))
                                Text(verbatim: "\(summary.activeOccupants)")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(VColor.exec)
                        }

                        if summary.riskRooms > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 7))
                                Text(verbatim: "\(summary.riskRooms)")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(VColor.bad)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? VColor.accent.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? VColor.accent : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
