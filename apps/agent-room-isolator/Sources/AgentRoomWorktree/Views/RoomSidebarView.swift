import NoticeBannerUIKit
import SwiftUI

struct RoomSidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner(model.errorMessage)
            if model.binds.isEmpty {
                ContentUnavailableView(
                    model.L(.sidebarEmptyTitle),
                    systemImage: "door.left.hand.closed",
                    description: Text(model.L(.sidebarEmptyBody))
                )
            } else {
                List(model.binds, selection: $model.selectedRoomID) { bind in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bind.slug)
                            .font(.headline)
                        Text(bind.task)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(bind.roomID)
                    .accessibilityLabel(bind.slug)
                }
            }
        }
        .navigationTitle(model.L(.windowTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showProvision = true
                } label: {
                    Label(model.L(.provisionTitle), systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label(model.L(.menuRefresh), systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
