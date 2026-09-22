import SwiftUI
import AgentRoomWorktreeCore

struct RoomConceptSection: View {
    @Bindable var model: AppModel
    let bind: RoomWorktreeBind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.L(.sectionConcept))
                .font(.title3.weight(.semibold))
            LabeledContent(model.L(.detailSlug), value: bind.slug)
            LabeledContent(model.L(.detailTask)) {
                Text(bind.task).textSelection(.enabled)
            }
            LabeledContent(model.L(.detailVerify)) {
                Text(bind.verify)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent(model.L(.detailRoomID)) {
                Text(bind.roomID).font(.caption.monospaced())
            }
            LabeledContent(model.L(.detailPlanID)) {
                Text(bind.planID.isEmpty ? "—" : bind.planID).font(.caption.monospaced())
            }
            LabeledContent(model.L(.detailTenant), value: bind.tenantID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.L(.sectionConcept))
    }
}
