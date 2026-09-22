import SwiftUI

struct ProvisionSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.L(.provisionTitle))
                .font(.title2.weight(.semibold))
            Text(model.L(.provisionHint))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Form {
                TextField(model.L(.detailTask), text: $model.draftTask)
                TextField(model.L(.detailVerify), text: $model.draftVerify)
                TextField(model.L(.detailRepo), text: $model.draftRepo)
                TextField(model.L(.detailOccupant), text: $model.draftOccupant)
                TextField(model.L(.detailTenant), text: $model.draftTenant)
                Toggle(model.L(.provisionDryRun), isOn: $model.draftDryRun)
            }

            HStack {
                Button(model.L(.provisionCancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.L(.provisionRun)) {
                    Task {
                        await model.provisionDraft()
                        if model.errorMessage == nil { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(formIncomplete)
                .accessibilityLabel(model.L(.provisionRun))
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }

    private var missingConcept: Bool {
        model.draftTask.isEmpty || model.draftVerify.isEmpty
    }

    private var missingBind: Bool {
        model.draftRepo.isEmpty || model.draftTenant.isEmpty
    }

    private var formIncomplete: Bool {
        let missingIdentity = missingBind || model.draftOccupant.isEmpty
        return missingConcept || missingIdentity
    }
}
