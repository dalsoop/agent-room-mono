import SwiftUI
import LocalizationKit
import SettingsUIKit
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        StandardSettingsForm(
            languageTitle: model.L(.settingsLanguage),
            language: Binding(
                get: { model.loc.language },
                set: { model.loc.setLanguage($0) }
            ),
            translationCoverage: TranslationCoverage(hardcodedUICount: 12),
            launchAtLoginTitle: model.L(.settingsLaunchAtLogin)
        ) {
            Section(model.L(.menubarTitle)) {
                Text(model.L(.settingsEditInMain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(model.L(.SettingsViewTextfield), text: $model.pathDraft)
                TextField("GitHub repo", text: $model.repoDraft)
                Button(model.L(.actionSave)) { model.applyConfigDrafts() }
            }
        }
        .padding()
    }
}
