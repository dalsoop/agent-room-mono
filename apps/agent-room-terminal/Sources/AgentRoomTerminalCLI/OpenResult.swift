import AgentRoomTerminalCore
import Foundation

extension OpenCommand {
    struct OpenResultInput {
        var hit: LedgerRoomHit
        var preset: RoomWallPreset
        var tool: AgentRoomTool
        var assembled: RoomAssemblyResult
        var opened: OpenPolicy.OpenedSession
        var wallMode: String
        var verdict: OpenPolicy.VerdictStatus
        var markdown: String
        var credentialSeed: AgentCredentialInjector.SeedOutcome
    }

    static func openResult(_ input: OpenResultInput) -> [String: Any] {
        var result: [String: Any] = [
            "roomID": input.hit.roomID,
            "path": input.assembled.roomURL.path,
            "preset": input.preset.rawValue,
            "tool": input.tool.rawValue,
            "sessionID": input.opened.sessionID,
            "wallMode": input.wallMode,
            "excludedTools": input.assembled.excludedTools,
            "linkedTools": input.assembled.linkedTools,
            "roomMarkdown": input.markdown,
            "dryRun": false,
            "seatbelt": input.opened.seatbelt,
            "reused": input.opened.reused,
            "sessionRole": input.opened.sessionRole,
            "verdictRunnable": input.verdict.runnable,
            "credentialSeed": input.credentialSeed.rawValue,
            "unseedOnClose": true,
            "network": input.opened.network.jsonObject,
        ]
        if !input.verdict.reason.isEmpty {
            result["verdictReason"] = input.verdict.reason
        }
        if input.preset == .open {
            result["openMark"] = openMark
        }
        if let predecessor = input.opened.predecessorSession, !predecessor.isEmpty {
            result["predecessorSession"] = predecessor
        }
        if let ledger = input.opened.ledger, !ledger.isEmpty {
            result["ledger"] = ledger
        }
        return result
    }
}
