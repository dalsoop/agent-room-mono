import AgentRoomTerminalCore
import Foundation
import SwiftUI

/// RoomDetailView에서 사용되는 각 탭별 하위 섹션 뷰 및 문서 분석 유틸리티.
@MainActor
enum RoomDetailHelper {
    static func roomFolder(for roomID: String) -> URL? {
        do {
            return try RoomFolderLocator.find(roomID: roomID)
        } catch {
            return nil
        }
    }

    static func resolveDocument(for node: RoomSummary) -> RoomDocument? {
        guard let folder = roomFolder(for: node.id) else { return nil }
        do {
            return try RoomDocument.load(from: folder)
        } catch {
            return nil
        }
    }

    static func resolveTask(for node: RoomSummary) -> String {
        if let doc = resolveDocument(for: node), !doc.task.isEmpty {
            return doc.task
        }
        return parseLine(prefix: "일:", in: node.roomMarkdown) ??
               parseLine(prefix: "작업:", in: node.roomMarkdown) ??
               parseLine(prefix: "task:", in: node.roomMarkdown) ?? ""
    }

    static func resolveVerdict(for node: RoomSummary) -> String {
        if let doc = resolveDocument(for: node), !doc.verdict.isEmpty {
            return doc.verdict
        }
        return parseLine(prefix: "완료:", in: node.roomMarkdown) ??
               parseLine(prefix: "verdict:", in: node.roomMarkdown) ?? ""
    }

    static func resolveWritePaths(for node: RoomSummary) -> [String] {
        if let doc = resolveDocument(for: node) {
            return doc.walls.writePaths
        }
        return []
    }

    static func resolveNetwork(for node: RoomSummary, model: AppModel) -> String? {
        guard let doc = resolveDocument(for: node) else { return nil }
        return switch doc.walls.network {
        case .open: model.L(.networkOpen)
        case .closed: model.L(.networkBlocked)
        case .allow(let domains): "\(model.L(.networkAllowed)): \(domains.joined(separator: ", "))"
        }
    }

    static func resolveHandoffNotes(for node: RoomSummary) -> [String] {
        guard let folder = roomFolder(for: node.id) else {
            return node.bottles.map(\.id)
        }
        let handoffDir = folder.appendingPathComponent("handoff", isDirectory: true)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: handoffDir,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return node.bottles.map(\.id)
        }
        let sorted = files.filter { $0.pathExtension == "json" }.sorted { f1, f2 in
            let d1 = fileModificationDate(of: f1)
            let d2 = fileModificationDate(of: f2)
            return d1 > d2
        }
        var notes: [String] = []
        for file in sorted {
            do {
                let data = try Data(contentsOf: file)
                let obj = try JSONSerialization.jsonObject(with: data)
                if let json = obj as? [String: Any],
                   let note = json["note"] as? String, !note.isEmpty {
                    notes.append(note)
                } else {
                    notes.append(file.deletingPathExtension().lastPathComponent)
                }
            } catch {
                notes.append(file.deletingPathExtension().lastPathComponent)
            }
        }
        return notes.isEmpty ? node.bottles.map(\.id) : notes
    }

    private static func fileModificationDate(of url: URL) -> Date {
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return values.contentModificationDate ?? .distantPast
        } catch {
            return .distantPast
        }
    }

    private static func parseLine(prefix: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
        }
        return nil
    }
}

struct RoomDetailItemView: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(bodyText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
