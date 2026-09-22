import SwiftUI

struct RoomStandUpSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var slug: String = ""
    @State private var tenant: String = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.L(.standUpTitle))
                .font(.headline)
            if model.roomSurface.standUpBlueprints.isEmpty || model.roomSurface.standUpTenants.isEmpty {
                Text(model.L(.standUpEmpty))
                    .foregroundStyle(.secondary)
            } else {
                Picker(model.L(.standUpBlueprint), selection: $slug) {
                    ForEach(model.roomSurface.standUpBlueprints) { pick in
                        Text(pick.title).tag(pick.slug)
                    }
                }
                Picker(model.L(.standUpTenant), selection: $tenant) {
                    ForEach(model.roomSurface.standUpTenants, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
            HStack {
                Spacer()
                Button(model.L(.standUpCancel)) { isPresented = false }
                Button(model.L(.standUpConfirm)) {
                    Task { await confirm() }
                }
                .disabled(!canConfirm || busy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .task { await prepare() }
    }

    private var canConfirm: Bool {
        !slug.isEmpty && !tenant.isEmpty
    }

    private func prepare() async {
        await model.loadStandUpCatalog()
        if slug.isEmpty {
            slug = model.roomSurface.standUpBlueprints.first?.slug ?? ""
        }
        if tenant.isEmpty {
            tenant = model.roomSurface.standUpTenants.first ?? ""
        }
    }

    private func confirm() async {
        busy = true
        await model.standUp(slug: slug, tenant: tenant)
        busy = false
        if model.errorMessage == nil {
            isPresented = false
        }
    }
}
