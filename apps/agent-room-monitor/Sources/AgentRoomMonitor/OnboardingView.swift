import OnboardingUIKit
import SwiftUI

/// 첫 실행 설정 온보딩. 브로셔(기능 나열 + 「시작하기」)는 온보딩이 아니다.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    var defaultsApplied: Bool
    var requiredDone: Bool
    var onEnableRequired: (() -> Void)?
    var onSkip: () -> Void
    var onFinished: () -> Void

    var body: some View {
        OnboardingChecklistView(
            title: app.L(.onboardingTitle),
            subtitle: app.L(.onboardingSubtitle),
            rows: rows,
            skipTitle: app.L(.onboardingSkip),
            finishEnabledTitle: app.L(.onboardingFinish),
            finishDisabledTitle: app.L(.onboardingFinishBlocked),
            canFinish: requiredDone,
            onSkip: onSkip,
            onFinish: onFinished
        )
    }

    private var rows: [OnboardingRow] {
        var list = [
            OnboardingRow(
                id: "defaults",
                title: app.L(.onboardingDefaultsTitle),
                detail: app.L(.onboardingDefaultsBody),
                done: defaultsApplied
            ),
        ]
        if let onEnableRequired {
            list.append(
                OnboardingRow(
                    id: "required",
                    title: app.L(.onboardingRequiredTitle),
                    detail: app.L(.onboardingRequiredBody),
                    done: requiredDone,
                    actionTitle: app.L(.onboardingRequiredAction),
                    action: onEnableRequired
                )
            )
        }
        return list
    }
}
