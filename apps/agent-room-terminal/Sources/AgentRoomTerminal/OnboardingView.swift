import LocalizationKit
import OnboardingUIKit
import SwiftUI

/// 첫 실행 사용법 소개 온보딩.
///
/// 레포 규율(CLAUDE.md): 온보딩은 질문형 위저드가 아니라 사용법 소개여야 한다.
/// 방(room) 격리 개념과 세 겹 벽(제한 셸 + 전용 PATH + seatbelt 샌드박스)을 한눈에 소개한다.
struct OnboardingView: View {
    var onStart: () -> Void
    var onSkip: (() -> Void)?

    init(onStart: @escaping () -> Void = {}, onSkip: (() -> Void)? = nil) {
        self.onStart = onStart
        self.onSkip = onSkip
    }

    /// 이전 체크리스트 호출부와의 하위 호환성 유지
    init(
        defaultsApplied: Bool = true,
        requiredDone: Bool = true,
        onEnableRequired: (() -> Void)? = nil,
        onSkip: @escaping () -> Void = {},
        onFinished: @escaping () -> Void = {}
    ) {
        self.onStart = onFinished
        self.onSkip = onSkip
    }

    private let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    var body: some View {
        OnboardingIntroView(
            title: L(.onboardingTitle),
            subtitle: L(.onboardingSubtitle),
            features: [
                OnboardingFeature(
                    symbol: "macwindow.on.rectangle",
                    title: L(.onboardingFeatureRoomTitle),
                    detail: L(.onboardingFeatureRoomDetail)
                ),
                OnboardingFeature(
                    symbol: "terminal",
                    title: L(.onboardingFeatureShellTitle),
                    detail: L(.onboardingFeatureShellDetail)
                ),
                OnboardingFeature(
                    symbol: "folder.badge.gearshape",
                    title: L(.onboardingFeaturePathTitle),
                    detail: L(.onboardingFeaturePathDetail)
                ),
                OnboardingFeature(
                    symbol: "shield.lefthalf.filled",
                    title: L(.onboardingFeatureSeatbeltTitle),
                    detail: L(.onboardingFeatureSeatbeltDetail)
                ),
            ],
            note: L(.onboardingNote),
            startTitle: L(.onboardingStart),
            onStart: onStart,
            skipTitle: onSkip != nil ? L(.onboardingSkip) : nil,
            onSkip: onSkip
        )
    }
}
