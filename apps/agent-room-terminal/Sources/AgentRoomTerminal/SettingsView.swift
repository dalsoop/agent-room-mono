import SwiftUI
import LocalizationKit
import SettingsUIKit
import SparkleUpdateKit

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        StandardSettingsForm(
            languageTitle: model.L(.settingsLanguage),
            language: Binding(
                get: { model.loc.language },
                set: { model.loc.setLanguage($0) }
            ),
            launchAtLoginTitle: model.L(.settingsLaunchAtLogin)
        ) {
            AdvancedTuningSection(model: model)
        }
        .padding()
        .sparkleUpdates()
    }
}

private struct AdvancedTuningSection: View {
    @Bindable var model: AppModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            advancedContent
        } label: {
            Text(model.L(.settingsAdvanced))
                .font(.headline)
        }
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            timingAndBufferItems
            handoffAndPromotionItems
            restoreButton
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var timingAndBufferItems: some View {
        tuningItem(
            title: model.L(.settingsIdleSeconds),
            description: model.L(.settingsIdleSecondsDesc)
        ) {
            intStepper(
                model.L(.settingsIdleSeconds),
                Binding(
                    get: { Int(model.tuning.idleSeconds) },
                    set: { model.tuning.idleSeconds = Double($0); model.persistTuning() }
                ),
                5...600
            )
        }

        tuningItem(
            title: model.L(.settingsRingLines),
            description: model.L(.settingsRingLinesDesc)
        ) {
            intStepper(
                model.L(.settingsRingLines),
                Binding(
                    get: { model.tuning.ringLines },
                    set: { model.tuning.ringLines = $0; model.persistTuning() }
                ),
                100...50_000
            )
        }
    }

    @ViewBuilder
    private var handoffAndPromotionItems: some View {
        tuningItem(
            title: model.L(.settingsHandoffFactor),
            description: model.L(.settingsHandoffFactorDesc)
        ) {
            factorField
        }

        tuningItem(
            title: model.L(.settingsReplayCount),
            description: model.L(.settingsReplayCountDesc)
        ) {
            intStepper(
                model.L(.settingsReplayCount),
                Binding(
                    get: { model.tuning.replayCount },
                    set: { model.tuning.replayCount = $0; model.persistTuning() }
                ),
                1...20
            )
        }

        tuningItem(
            title: model.L(.settingsPromoteSuccesses),
            description: model.L(.settingsPromoteSuccessesDesc)
        ) {
            intStepper(
                model.L(.settingsPromoteSuccesses),
                Binding(
                    get: { model.tuning.promoteSuccesses },
                    set: { model.tuning.promoteSuccesses = $0; model.persistTuning() }
                ),
                1...50
            )
        }
    }

    private var restoreButton: some View {
        Button(model.L(.settingsRestoreFactory)) {
            model.restoreFactoryTuning()
        }
        .padding(.top, 4)
    }

    private func tuningItem<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var factorField: some View {
        LabeledContent(model.L(.settingsHandoffFactor)) {
            TextField(
                model.L(.settingsHandoffFactor),
                value: Binding(
                    get: { model.tuning.handoffFactor },
                    set: { model.tuning.handoffFactor = $0; model.persistTuning() }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .frame(width: 88)
            .multilineTextAlignment(.trailing)
        }
    }

    private func intStepper(
        _ title: String,
        _ value: Binding<Int>,
        _ range: ClosedRange<Int>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
                Stepper("", value: value, in: range)
                    .labelsHidden()
            }
        }
    }
}
