import StatusIndicatorUIKit
import SwiftUI
import AgentRoomWorktreeCore

struct RoomLedgerSection: View {
    @Bindable var model: AppModel
    let bind: RoomWorktreeBind

    var body: some View {
        let ledger = model.trace?.ledger
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.L(.sectionLedger))
                    .font(.title3.weight(.semibold))
                Spacer()
                StatusBadge(
                    title: (ledger?.ok == true) ? model.L(.ledgerLinked) : model.L(.ledgerMissing),
                    tone: (ledger?.ok == true) ? .success : .warning,
                    showDot: true
                )
            }
            LabeledContent(model.L(.detailPlanID), value: bind.planID.isEmpty ? "—" : bind.planID)
            if let ledger {
                if !ledger.state.isEmpty {
                    LabeledContent(model.L(.ledgerState), value: ledger.state)
                }
                if !ledger.occupant.isEmpty {
                    LabeledContent(model.L(.ledgerOccupant), value: ledger.occupant)
                }
                if !ledger.ok, !ledger.error.isEmpty {
                    Text(ledger.error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(model.L(.sectionLedger))
    }
}