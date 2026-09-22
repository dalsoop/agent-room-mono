import SwiftUI
import AgentRoomTerminalCore

struct RoomBriefingHeaderView: View {
    @Bindable var model: AppModel
    let room: RoomSummary
    @State private var isExpanded: Bool = true

    private var fields: BriefingFields {
        if let doc = loadDocument() {
            let input = BriefingInput(
                task: doc.task,
                slug: doc.slug,
                verdict: doc.verdict,
                allowWrite: doc.walls.writePaths,
                toolbelt: doc.toolbelt,
                preset: doc.preset,
                noneText: model.L(.briefingNone),
                hostPathText: model.L(.briefingHostPath),
                sandboxBackend: doc.sandboxBackend ?? "seatbelt"
            )
            return BriefingFieldsResolver.resolve(
                input: input,
                defaultToolsText: model.L(.briefingDefaultTools)
            )
        }
        return BriefingFields(
            task: room.title.isEmpty ? room.id : room.title,
            verdict: (room.status == .done) ? model.L(.briefingDone) : model.L(.briefingInProgress),
            writePaths: model.L(.briefingNone),
            tools: model.L(.briefingDefaultTools)
        )
    }

    private func loadDocument() -> RoomDocument? {
        guard let folder = try? RoomFolderLocator.find(roomID: room.id) else { return nil }
        do {
            return try RoomDocument.load(from: folder)
        } catch {
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(model.L(.briefingTitle))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if !isExpanded {
                    Text(fields.task)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 0, alignment: .leading)
                        .truncationMode(.tail)
                }

                Spacer()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    briefingLine(label: model.L(.briefingTask), value: fields.task)
                    briefingLine(label: model.L(.briefingVerdict), value: fields.verdict)
                    briefingLine(label: model.L(.briefingWritePaths), value: fields.writePaths)
                    briefingLine(label: model.L(.briefingTools), value: fields.tools)
                    briefingLine(label: model.L(.briefingSandbox), value: fields.sandboxBackend)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }

    private func briefingLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(minWidth: 0, alignment: .leading)
        }
    }
}
