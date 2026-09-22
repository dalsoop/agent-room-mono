import SwiftUI
import AgentRoomTerminalCore

struct RoomResultSectionView: View {
    var model: AppModel
    var node: RoomSummary
    var roomFolderResolver: (String) -> URL?

    var body: some View {
        let fields = resolveResult()
        if fields.hasResult || fields.ledgerPhase != nil || fields.lastVerdictExit != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.L(.detailResult))
                    .font(.subheadline.weight(.semibold))

                if let status = fields.resultStatus {
                    statusRow(status: status, fields: fields)
                }

                if let phase = fields.ledgerPhase {
                    let exitStr = fields.ledgerExitCode.map { " exitCode=\($0)" } ?? ""
                    Text("phase=\(phase)\(exitStr)")
                        .font(.system(.caption, design: .monospaced))
                }

                if let exit = fields.lastVerdictExit {
                    Text("verdict exit=\(exit)")
                        .font(.system(.caption, design: .monospaced))
                }

                if let logPath = fields.launchLogPath {
                    Button(model.L(.resultOpenLog)) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow(status: String, fields: RoomResultFields) -> some View {
        let notes = fields.resultNotes.map { String($0.prefix(120)) } ?? ""
        let commits = fields.resultCommitCount.map { "commits=\($0)" } ?? ""
        Text("status=\(status) \(commits)".trimmingCharacters(in: .whitespaces))
            .font(.system(.caption, design: .monospaced))
        if !notes.isEmpty {
            Text(notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func resolveResult() -> RoomResultFields {
        RoomResultResolver.resolve(
            roomID: node.id,
            roomDirectoryResolver: { roomFolderResolver($0) },
            workdirResolver: { id in
                guard let folder = roomFolderResolver(id) else { return nil }
                let specURL = folder.appendingPathComponent("spec.json", isDirectory: false)
                let data: Data
                do { data = try Data(contentsOf: specURL) } catch { return nil }
                let json: [String: Any]
                do {
                    guard let p = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                    json = p
                } catch { return nil }
                return json["workdir"] as? String
            },
            fileReader: { url in
                do { return try Data(contentsOf: url) } catch { return nil }
            }
        )
    }
}
