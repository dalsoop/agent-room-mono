import Foundation
import RoomKit

/// Codex 실측: `sessions/YYYY/MM/DD/rollout-<ts>-<sessionID>.jsonl`. cwd 는 파일 안 meta.
enum CodexTranscriptRule {
    static func resolve(
        sessionID: String,
        workdir: String,
        homeDirectory: String,
        environment: [String: String],
        files: any RoomFileIO
    ) -> TranscriptBinding {
        let empty = TranscriptBinding(
            tool: AgentRoomTool.codex.rawValue,
            path: "",
            reason: TranscriptBindingReason.noRule
        )
        guard !sessionID.isEmpty else { return empty }
        let root = BudgetHostPaths.codexSessions(environment: environment, homeDirectory: homeDirectory)
        let matches = rolloutFiles(sessionID: sessionID, under: root, files: files)
        let chosen = firstMatching(matches, workdir: workdir, files: files)
        guard let path = chosen else { return empty }
        return TranscriptBinding(
            tool: AgentRoomTool.codex.rawValue,
            path: path,
            reason: TranscriptBindingReason.resolved
        )
    }

    static func isRolloutName(_ name: String, sessionID: String) -> Bool {
        name.hasPrefix("rollout-") && name.hasSuffix("-\(sessionID).jsonl")
    }

    static func rolloutFiles(sessionID: String, under root: URL, files: any RoomFileIO) -> [URL] {
        guard files.isDirectory(atPath: root.path) else { return [] }
        var found: [URL] = []
        for year in directoryNames(in: root, files: files) {
            let yearURL = root.appendingPathComponent(year)
            for month in directoryNames(in: yearURL, files: files) {
                let monthURL = yearURL.appendingPathComponent(month)
                appendDayFiles(sessionID: sessionID, monthURL: monthURL, files: files, into: &found)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    private static func appendDayFiles(
        sessionID: String,
        monthURL: URL,
        files: any RoomFileIO,
        into found: inout [URL]
    ) {
        for day in directoryNames(in: monthURL, files: files) {
            let dayURL = monthURL.appendingPathComponent(day)
            let names: [String]
            do {
                names = try files.contentsOfDirectory(atPath: dayURL.path)
            } catch {
                continue
            }
            for name in names where isRolloutName(name, sessionID: sessionID) {
                found.append(dayURL.appendingPathComponent(name))
            }
        }
    }

    private static func directoryNames(in url: URL, files: any RoomFileIO) -> [String] {
        guard files.isDirectory(atPath: url.path) else { return [] }
        let names: [String]
        do {
            names = try files.contentsOfDirectory(atPath: url.path)
        } catch {
            return []
        }
        return names.filter { files.isDirectory(atPath: url.appendingPathComponent($0).path) }.sorted()
    }

    private static func firstMatching(_ urls: [URL], workdir: String, files: any RoomFileIO) -> String? {
        let target = workdir.isEmpty ? nil : URL(fileURLWithPath: workdir).standardized.path
        for url in urls {
            if matchesWorkdir(url, target: target, files: files) { return url.path }
        }
        return nil
    }

    private static func matchesWorkdir(_ url: URL, target: String?, files: any RoomFileIO) -> Bool {
        guard let target else { return true }
        let cwd: String
        do {
            cwd = try metaCwd(files.read(from: url)) ?? ""
        } catch {
            return false
        }
        guard !cwd.isEmpty else { return true }
        return URL(fileURLWithPath: cwd).standardized.path == target
    }

    static func metaCwd(_ data: Data) throws -> String? {
        guard let line = firstLine(data) else { return nil }
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        return value.object?["payload"]?.object?["cwd"]?.string
    }

    private static func firstLine(_ data: Data) -> String? {
        let newline = UInt8(ascii: "\n")
        let slice: Data
        if let index = data.firstIndex(of: newline) {
            slice = data[data.startIndex..<index]
        } else {
            slice = data
        }
        return String(data: slice, encoding: .utf8)
    }
}
