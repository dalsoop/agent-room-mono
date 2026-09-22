import NoticeBannerUIKit
import SwiftUI
import WindowChromeKit

/// 주 화면 — 왼쪽 방 목록, 오른쪽 개념·워크트리·MD.
struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        TwoColumnCatalog {
            RoomSidebarView(model: model)
        } detail: {
            Group {
                if model.selectedBind != nil {
                    RoomDetailView(model: model)
                } else {
                    EmptyRoomPane(model: model)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .sheet(isPresented: $model.showProvision) {
            ProvisionSheet(model: model)
        }
        .task { await model.refresh() }
    }
}
