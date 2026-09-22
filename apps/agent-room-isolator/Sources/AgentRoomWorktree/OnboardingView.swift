import OnboardingUIKit
import SwiftUI

/// First-run checklist. Intro cards use `OnboardingIntroView`; multi-step uses `OnboardingWizardShell`.
///
/// Gate MainView only when required items remain. Recommended defaults apply in `.task`
/// without a form; items that need a system prompt get a button.
/// Skill: `.claude/skills/app-onboarding/SKILL.md`
struct OnboardingView: View {
    @Bindable var model: AppModel
    var defaultsApplied: Bool
    var requiredDone: Bool
    var onEnableRequired: (() -> Void)?
    var onSkip: () -> Void
    var onFinished: () -> Void

    var body: some View {
        OnboardingChecklistView(
            title: model.L(.onboardTitle),
            subtitle: model.L(.onboardSubtitle),
            rows: rows,
            skipTitle: model.L(.onboardSkip),
            finishEnabledTitle: model.L(.onboardFinish),
            finishDisabledTitle: model.L(.onboardNeedRequired),
            canFinish: requiredDone,
            onSkip: onSkip,
            onFinish: onFinished
        )
    }

    private var rows: [OnboardingRow] {
        var list = [
            OnboardingRow(
                id: "defaults",
                title: model.L(.onboardDefaults),
                detail: model.L(.onboardDefaultsDetail),
                done: defaultsApplied
            ),
        ]
        if let onEnableRequired {
            list.append(
                OnboardingRow(
                    id: "required",
                    title: model.L(.onboardRequired),
                    detail: model.L(.onboardRequiredDetail),
                    done: requiredDone,
                    actionTitle: model.L(.onboardTurnOn),
                    action: onEnableRequired
                )
            )
        }
        return list
    }
}
