import SwiftUI
import AgentRoomWorktreeCore

struct RoomDetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            if let bind = model.selectedBind {
                LazyVStack(alignment: .leading, spacing: 20) {
                    RoomConceptSection(model: model, bind: bind)
                    Divider()
                    RoomLedgerSection(model: model, bind: bind)
                    Divider()
                    RoomWorktreeSection(model: model, bind: bind)
                    Divider()
                    RoomDocumentsSection(model: model)
                }
                .padding(24)
            }
        }
        .navigationTitle(model.selectedBind?.slug ?? model.L(.windowTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.emitSelectedMd() }
                } label: {
                    Label(model.L(.actionEmitMd), systemImage: "doc.badge.plus")
                }
                .disabled(model.selectedBind == nil)
            }
        }
    }
}
