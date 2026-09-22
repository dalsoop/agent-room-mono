import SwiftUI
import AgentRoomMonitorCore

/// 좌상단 HUD — 집계 + 호스트 텔레메트리 (전부 실측 스냅샷).
struct HUDCard: View {
    @Environment(AppModel.self) private var app
    let world: VWorld

    var body: some View {
        let aggregate = world.host.aggregate()
        VStack(alignment: .leading, spacing: 3) {
            Text(app.L(.hudTitle)).font(.system(size: 14, weight: .bold))
            Text(String(format: app.L(.hudSubtitle), world.telemetry.at))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider().padding(.vertical, 2)
            row(app.L(.hudRunning), "\(aggregate.exec)", VColor.exec)
            row(app.L(.hudBlocked), "\(aggregate.block)", VColor.bad)
            row(app.L(.hudGates), "\(aggregate.gate)", VColor.gate)
            row(app.L(.hudCPU), String(format: app.L(.hudCores), "\(world.telemetry.load1)", "\(world.telemetry.ncpu)"), nil)
            row(app.L(.hudRAM), "\(world.telemetry.memUsed) / \(world.telemetry.memTot) GB", nil)
            row(app.L(.hudNet), "\(world.telemetry.downKB) / \(world.telemetry.upKB) KB/s", nil)
            reachRow(app.L(.hudIntNet), ok: world.telemetry.intNet)
            reachRow(app.L(.hudExtNet), ok: world.telemetry.extNet)
        }
        .font(.system(size: 11.5))
        .padding(12)
        .frame(width: 222, alignment: .leading)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
    }

    private func row(_ key: String, _ value: String, _ color: Color?) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color ?? .primary)
        }
    }

    private func reachRow(_ key: String, ok: Bool) -> some View {
        row(key, ok ? "✓" : app.L(.hudReachFail), ok ? VColor.exec : VColor.bad)
    }
}

/// 좌하단 범례.
struct LegendCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                key(VColor.exec, app.L(.stateExec))
                key(VColor.bad, app.L(.stateBlock))
                key(VColor.gate, app.L(.stateGate))
                key(Color(red: 0.47, green: 0.51, blue: 0.56), app.L(.stateNeutral))
            }
            Text(app.L(.legendLine1)).foregroundStyle(.secondary)
            Text(app.L(.legendLine2)).foregroundStyle(.secondary)
        }
        .font(.system(size: 10.5))
        .padding(10)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }
}

/// 비교 모드 — SnapshotArchive 최근 두 장의 변화만.
struct ComparePane: View {
    @Environment(AppModel.self) private var app
    let board: BoardModel

    var body: some View {
        if let diff = board.compareDiff, !diff.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(app.L(.compareTitle)).font(.system(size: 13, weight: .bold))
                    diffColumn(app.L(.compareAdded), diff.added, VColor.exec)
                    diffColumn(app.L(.compareRemoved), diff.removed, VColor.bad)
                    diffColumn(app.L(.compareChanged), diff.changed, VColor.gate)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 6) {
                Text(app.L(.compareTitle)).font(.system(size: 13, weight: .bold))
                Text(app.L(.compareBody))
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func diffColumn(_ title: String, _ ids: [String], _ color: Color) -> some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) (\(ids.count))").font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                ForEach(ids, id: \.self) { id in
                    let name = board.world.host.find(id)?.name ?? id
                    Text("\(id) — \(name)").font(.system(size: 11, design: .monospaced))
                }
            }
        }
    }
}
