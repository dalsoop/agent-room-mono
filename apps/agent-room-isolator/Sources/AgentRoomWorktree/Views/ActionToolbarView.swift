import SwiftUI
import AgentRoomWorktreeCore

/// 하단 보조 제어 컴포넌트 — 빠른 작업 및 메타 정보 표시.
///
/// 컴포넌트 분할을 통해 MainView 비대화(God-file)를 방지하며 150줄 이내를 유지합니다.
struct ActionToolbarView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack {
            Text(RoomWorktreePaths.slug)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(model.L(.provisionTitle)) {
                model.showProvision = true
            }
            .buttonStyle(.borderedProminent)

            Button(model.L(.menuRefresh)) {
                Task { await model.refresh() }
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $model.showProvision) {
                ProvisionSheet(model: model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
