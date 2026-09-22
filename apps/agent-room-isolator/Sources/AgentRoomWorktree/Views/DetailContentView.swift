import SwiftUI
import AgentRoomWorktreeCore

struct DetailContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.binds.isEmpty {
                Text(model.L(.detailEmpty))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                List(model.binds) { bind in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bind.slug)
                            .font(.headline)
                        LabeledContent(model.L(.detailTask), value: bind.task)
                        LabeledContent(model.L(.detailWorktree), value: bind.worktreePath)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
