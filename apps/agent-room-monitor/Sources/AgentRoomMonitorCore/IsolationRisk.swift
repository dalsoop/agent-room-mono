import Foundation
import AppPathsKit

/// 방 벽(쓰기·도구·네트워크) 위험도. 선언된 경로만 본다. OS 강제가 아니다.
public enum IsolationRisk {
    public static let manyToolsThreshold = 5

    /// 홈 디렉터리 전체(또는 `/**`)에 쓰기가 열려 있으면 위험.
    public static func isHomeWideWrite(_ path: String, home: String = DurableAppLayout.defaultHomeDirectory.path) -> Bool {
        let homePath = URL(fileURLWithPath: home).standardizedFileURL.path
        let expanded = (path as NSString).expandingTildeInPath
        let normalized = expanded
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return checkHomeWideMatch(normalized: normalized, homePath: homePath)
    }

    private static func checkHomeWideMatch(normalized: String, homePath: String) -> Bool {
        if standardizedFilePath(normalized) == homePath { return true }
        let suffixes = ["/**", "/*", "/", "/**/*", "/**/**"]
        for suffix in suffixes where normalized == homePath + suffix {
            return true
        }
        guard normalized.hasPrefix(homePath + "/") else { return false }
        let rest = String(normalized.dropFirst(homePath.count + 1))
        return ["*", "**", "**/*"].contains(rest)
    }

    public static func manyTools(_ count: Int) -> Bool {
        count >= manyToolsThreshold
    }

    public static func writesAreHomeWide(_ writes: [String], home: String = DurableAppLayout.defaultHomeDirectory.path) -> Bool {
        writes.contains { isHomeWideWrite($0, home: home) }
    }

    private static func standardizedFilePath(_ path: String) -> String {
        let withoutGlob = path
            .replacingOccurrences(of: "/**", with: "")
            .replacingOccurrences(of: "/*", with: "")
        if withoutGlob.hasSuffix("/") {
            return URL(fileURLWithPath: String(withoutGlob.dropLast())).standardizedFileURL.path
        }
        return URL(fileURLWithPath: withoutGlob).standardizedFileURL.path
    }
}
