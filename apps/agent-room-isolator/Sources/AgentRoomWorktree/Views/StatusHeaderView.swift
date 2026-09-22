import AppKit
import ClipboardActionUIKit
import NoticeBannerUIKit
import SwiftUI

/// 상단 상태 헤더 컴포넌트 — 상태 정보 및 클립보드 복사, 새로고침 액션 제공.
///
/// 컴포넌트 분할을 통해 MainView 비대화(God-file)를 방지하며 150줄 이내를 유지합니다.
struct StatusHeaderView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ErrorBanner(model.errorMessage)

            HStack(spacing: 8) {
                Text(model.status.isEmpty ? "—" : model.status)
                    .font(.title2)
                if !model.status.isEmpty {
                    CopyButton(text: model.status, iconOnly: true)
                }
                Spacer()
                Button(model.L(.menuRefresh)) {
                    Task { await model.refresh() }
                }
            }
        }
        .padding(16)
    }
}
