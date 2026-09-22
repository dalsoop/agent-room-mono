import Foundation

/// Grok 실측: `~/.grok/sessions/<percent-encode(cwd, unreserved)>/<sessionID>/updates.jsonl`.
enum GrokTranscriptRule {
    static func resolve(
        sessionID: String,
        workdir: String,
        homeDirectory: String,
        environment: [String: String],
        files: any RoomFileIO
    ) -> TranscriptBinding {
        let empty = TranscriptBinding(
            tool: AgentRoomTool.grok.rawValue,
            path: "",
            reason: TranscriptBindingReason.noRule
        )
        guard !sessionID.isEmpty, !workdir.isEmpty else { return empty }
        let root = BudgetHostPaths.grokSessions(environment: environment, homeDirectory: homeDirectory)
        let sessionDir = root
            .appendingPathComponent(percentEncode(workdir), isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let updates = sessionDir.appendingPathComponent("updates.jsonl")
        return pick(updates: updates, sessionDir: sessionDir, files: files) ?? empty
    }

    /// urllib.parse.quote(cwd, safe='') — 알파벳·숫자·`-._` 만 남기고 `/` 는 `%2F`.
    static func percentEncode(_ cwd: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._")
        return cwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? cwd
    }

    private static func pick(updates: URL, sessionDir: URL, files: any RoomFileIO) -> TranscriptBinding? {
        let path: String
        switch files.fileExists(atPath: updates.path) {
        case true:
            path = updates.path
        case false:
            guard files.isDirectory(atPath: sessionDir.path) else { return nil }
            path = sessionDir.path
        }
        return TranscriptBinding(
            tool: AgentRoomTool.grok.rawValue,
            path: path,
            reason: TranscriptBindingReason.resolved
        )
    }
}
