import Foundation
import PackageIdentityKit

/// CLI `version` / capabilities 의 마케팅 버전.
/// (1) 번들 Contents/Info.plist, (2) Versions/agent-room-terminal-swift 정본,
/// (3) Packaging/Info.plist, 모두 없으면 "dev".
public enum RoomCLIVersion {
    public static func current(
        processPath: String = Bundle.main.executablePath ?? CommandLine.arguments[0]
    ) -> String {
        resolve(processPath: processPath)
    }

    public static func resolve(processPath: String) -> String {
        let file = URL(fileURLWithPath: processPath)
        if let version = AppIdentityLocator.locate(executable: file)?.version {
            return version
        }
        if let version = readVersionsFile(startingNear: file) {
            return version
        }
        return "dev"
    }

    private static let versionFileName = "agent-room-terminal-swift"

    private static func readVersionsFile(startingNear executable: URL) -> String? {
        let resolved = AppIdentityLocator.resolveExecutable(executable)
        var dir = resolved.deletingLastPathComponent()
        let fm = FileManager.default
        for _ in 0..<24 {
            let candidate = dir
                .appendingPathComponent("Versions", isDirectory: true)
                .appendingPathComponent(versionFileName)
            if fm.fileExists(atPath: candidate.path) {
                do {
                    let content = try String(contentsOf: candidate, encoding: .utf8)
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                } catch {
                    return nil
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}
