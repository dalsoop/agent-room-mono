import StatusIndicatorUIKit
import SwiftUI
import AgentRoomWorktreeCore

struct RoomWorktreeSection: View {
    @Bindable var model: AppModel
    let bind: RoomWorktreeBind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.L(.sectionWorktree))
                    .font(.title3.weight(.semibold))
                Spacer()
                StatusBadge(
                    title: model.worktreePresent ? model.L(.worktreePresent) : model.L(.worktreeMissing),
                    tone: model.worktreePresent ? .success : .warning,
                    showDot: true
                )
            }
            LabeledContent(model.L(.detailWorktree)) {
                Text(bind.worktreePath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent(model.L(.detailBranch), value: bind.branch)
            LabeledContent(model.L(.detailRepo)) {
                Text(bind.repoPath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(model.L(.sectionWorktree))
    }
}
