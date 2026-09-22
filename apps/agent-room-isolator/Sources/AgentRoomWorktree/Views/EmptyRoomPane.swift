import SwiftUI

/// 방을 고르지 않았을 때 — 세 칸 안내 + 새 방 버튼.
struct EmptyRoomPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Text(model.L(.emptyHero))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 16) {
                paneCard(title: model.L(.sectionConcept), body: model.L(.emptyConcept), icon: "text.alignleft")
                paneCard(title: model.L(.sectionWorktree), body: model.L(.emptyWorktree), icon: "externaldrive")
                paneCard(title: model.L(.sectionDocuments), body: model.L(.emptyDocuments), icon: "doc.text")
            }

            Button {
                model.showProvision = true
            } label: {
                Label(model.L(.provisionTitle), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(model.L(.provisionTitle))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.L(.windowTitle))
    }

    private func paneCard(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
