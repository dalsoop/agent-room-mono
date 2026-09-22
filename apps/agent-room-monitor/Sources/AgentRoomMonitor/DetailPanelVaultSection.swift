import SwiftUI
import RoomKit
import AgentRoomMonitorCore

struct DetailPanelVaultSection: View {
    @Environment(AppModel.self) private var app
    let node: VNode

    private var summary: RoomVaultSummary? {
        guard node.kindRaw == "room" || node.kindRaw == "placement" else { return nil }
        let tenant = node.tenantID ?? "default"
        let layout = RoomVaultLayout.forRoom(tenant: tenant, roomID: node.id)
        return RoomVaultManager().summary(roomID: node.id, tenantID: tenant, in: layout)
    }

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.L(.panelVault))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.63, blue: 0.71))
                statusBadges(summary)
                statsRow(summary)
                localSkillsList(summary)
            }
        }
    }

    private func statusBadges(_ s: RoomVaultSummary) -> some View {
        HStack {
            vaultBadge(s.lifecycleState.rawValue.uppercased(), color: lifecycleColor(s.lifecycleState))
            if s.hasReceipt, let scope = s.receiptScope {
                let badgeText = s.receiptsCount > 1 ? "📜 \(scope) (\(s.receiptsCount))" : "📜 \(scope)"
                vaultBadge(badgeText, color: VColor.exec)
                if s.hasAutoBumped {
                    vaultBadge(app.L(.vaultAutoBumped), color: VColor.gate)
                }
            }
            Spacer()
            lifecycleActionButton(s)
        }
    }

    @ViewBuilder
    private func lifecycleActionButton(_ s: RoomVaultSummary) -> some View {
        // Room mutate actions: seal, archive, promote-skill
        let tenant = node.tenantID ?? "default"
        Group {
            switch s.lifecycleState {
            case .active:
                Button(String(localized: "Seal")) {
                    Task {
                        _ = await RoomMutationService().perform(.sealRoom(roomID: node.id, tenant: tenant, enforceDrain: false))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            case .sealed:
                Button(String(localized: "Archive")) {
                    Task {
                        _ = await RoomMutationService().perform(.archiveRoom(roomID: node.id, tenant: tenant))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            case .archived:
                EmptyView()
            }
        }
        .accessibilityIdentifier("mutate-lifecycle-actions")
    }

    private func lifecycleColor(_ state: RoomLifecycleState) -> Color {
        switch state {
        case .sealed:
            return VColor.exec
        case .archived:
            return Color.secondary
        case .active:
            return VColor.accent
        }
    }

    private func statsRow(_ s: RoomVaultSummary) -> some View {
        HStack(spacing: 12) {
            Text(String(format: app.L(.panelVaultCurated), s.stats.curatedArtifactCount))
                .font(.system(size: 11, design: .monospaced))
            Text(String(format: app.L(.panelVaultSkills), s.stats.skillCount))
                .font(.system(size: 11, design: .monospaced))
            Text(String(format: app.L(.panelVaultRaw), s.stats.rawSizeBytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func localSkillsList(_ s: RoomVaultSummary) -> some View {
        if !s.localSkills.isEmpty {
            Text(String(format: app.L(.panelLocalSkills), s.localSkills.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(s.localSkills, id: \.self) { skill in
                HStack(spacing: 6) {
                    Circle().fill(VColor.accent).frame(width: 6, height: 6)
                    Text(skill).monospaced().font(.system(size: 11))
                    Spacer()
                    Button(String(localized: "Promote")) {
                        let tenant = node.tenantID ?? "default"
                        Task {
                            _ = await RoomMutationService().perform(.promoteSkill(
                                roomID: node.id,
                                tenant: tenant,
                                skillName: skill,
                                targetDir: nil,
                                scope: "tenant",
                                force: false,
                                autoBump: true
                            ))
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(VColor.accent)
                }
            }
        }
    }

    private func vaultBadge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10.5))
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}
