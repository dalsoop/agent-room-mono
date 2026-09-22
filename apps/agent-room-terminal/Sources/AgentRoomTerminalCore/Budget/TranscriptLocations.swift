import Foundation
import SessionKit
import AgentSessionKit
import AppPathsKit

/// 도구별 전사(transcript) 위치 규칙.
/// Claude: `projects/<cwd 슬러그>/<session>.jsonl` — `/` 와 `.` 을 `-` 로.
/// Codex 실측(2026-09-10): `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<sessionID>.jsonl`,
///   첫 줄 `session_meta.payload.{cwd,session_id}`. cwd 는 경로에 안 들어간다.
/// Grok 실측(2026-09-10): `~/.grok/sessions/<percent-encode(cwd)>/<sessionID>/updates.jsonl`.
/// Gemini(agy): `conversation_summaries.db` 및 `conversations/<id>.db`.
public enum TranscriptLocations {
    public static func claudeProjectDirectory(cwd: String, homeDirectory: String = DurableAppLayout.defaultHomeDirectory.path) -> String {
        claudeProjectDirectory(cwd: cwd, configDirectory: (homeDirectory as NSString).appendingPathComponent(".claude"))
    }

    /// Claude Code 는 `CLAUDE_CONFIG_DIR` 이 있으면 전사를 `<그 폴더>/projects/<슬러그>/` 에 쓴다.
    public static func claudeProjectDirectory(cwd: String, configDirectory: String) -> String {
        let slug = cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        return (configDirectory as NSString)
            .appendingPathComponent("projects")
            .appending("/" + slug)
    }

    public static func antigravityRootDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = DurableAppLayout.defaultHomeDirectory.path
    ) -> String {
        BudgetHostPaths.antigravityCLI(environment: environment, homeDirectory: homeDirectory).path
    }

    public static func antigravitySummariesPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = DurableAppLayout.defaultHomeDirectory.path
    ) -> String {
        BudgetHostPaths.antigravitySummaries(environment: environment, homeDirectory: homeDirectory).path
    }

    public static func agyMatchingConversationPaths(
        workdir: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = DurableAppLayout.defaultHomeDirectory.path
    ) -> [String] {
        let root = antigravityRootDirectory(environment: environment, homeDirectory: homeDirectory)
        let reader = AntigravitySessionReader(root: root)
        let target = URL(fileURLWithPath: workdir).standardized.path
        return reader.discover()
            .filter { URL(fileURLWithPath: $0.cwd).standardized.path == target }
            .map(\.transcriptPath)
    }

    /// 방 세션의 작업 폴더를 기준으로 도구의 전사 위치. 모르면 nil.
    public static func defaultBinding(
        tool: AgentRoomTool,
        roomPath: String,
        homeDirectory: String = DurableAppLayout.defaultHomeDirectory.path,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let binding = resolve(
            tool: tool,
            sessionID: "",
            workdir: roomPath,
            homeDirectory: homeDirectory,
            environment: environment,
            files: FoundationRoomFileIO(),
            seat: nil
        )
        guard binding.reason == TranscriptBindingReason.resolved, !binding.path.isEmpty else {
            return nil
        }
        return binding.path
    }

    /// 결속 `transcript.path` 가 있으면 규칙보다 먼저 쓴다. 없으면 실측 규칙, 없으면 noRule.
    public static func resolve(
        tool: AgentRoomTool,
        sessionID: String,
        workdir: String,
        homeDirectory: String,
        environment: [String: String],
        files: any RoomFileIO,
        seat: SeatTranscriptRecord?
    ) -> TranscriptBinding {
        if let seatPath = seat?.transcriptPath, !seatPath.isEmpty {
            return TranscriptBinding(
                tool: tool.rawValue,
                path: seatPath,
                reason: TranscriptBindingReason.resolved
            )
        }
        return ruleBinding(
            tool: tool,
            sessionID: sessionID,
            workdir: workdir,
            homeDirectory: homeDirectory,
            environment: environment,
            files: files
        )
    }

    static func ruleBinding(
        tool: AgentRoomTool,
        sessionID: String,
        workdir: String,
        homeDirectory: String,
        environment: [String: String],
        files: any RoomFileIO
    ) -> TranscriptBinding {
        switch tool {
        case .claude:
            return claudeBinding(workdir: workdir, sessionID: sessionID)
        case .agy:
            return TranscriptBinding(
                tool: tool.rawValue,
                path: antigravitySummariesPath(environment: environment, homeDirectory: homeDirectory),
                reason: TranscriptBindingReason.resolved
            )
        case .grok:
            return GrokTranscriptRule.resolve(
                sessionID: sessionID,
                workdir: workdir,
                homeDirectory: homeDirectory,
                environment: environment,
                files: files
            )
        case .codex:
            return CodexTranscriptRule.resolve(
                sessionID: sessionID,
                workdir: workdir,
                homeDirectory: homeDirectory,
                environment: environment,
                files: files
            )
        }
    }

    static func claudeBinding(workdir: String, sessionID: String) -> TranscriptBinding {
        let configDir = AgentCredentialInjector.configDirName(
            tool: .claude, roomURL: URL(fileURLWithPath: workdir, isDirectory: true)
        )
        var path = claudeProjectDirectory(cwd: workdir, configDirectory: configDir.path)
        if !sessionID.isEmpty {
            path = (path as NSString).appendingPathComponent("\(sessionID).jsonl")
        }
        return TranscriptBinding(tool: AgentRoomTool.claude.rawValue, path: path, reason: TranscriptBindingReason.resolved)
    }
}
