import StatusIndicatorUIKit
import SwiftUI

struct RoomDocumentsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.L(.sectionDocuments))
                .font(.title3.weight(.semibold))
            ForEach(model.documents) { doc in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(doc.name)
                            .font(.headline)
                        Spacer()
                        StatusBadge(
                            title: doc.exists ? model.L(.docPresent) : model.L(.docMissing),
                            tone: doc.exists ? .success : .warning,
                            showDot: true
                        )
                    }
                    Text(doc.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !doc.preview.isEmpty {
                        Text(doc.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .accessibilityLabel("\(doc.name) \(doc.exists ? model.L(.docPresent) : model.L(.docMissing))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}