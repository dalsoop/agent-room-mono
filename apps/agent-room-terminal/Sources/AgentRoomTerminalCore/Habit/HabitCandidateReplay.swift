import Foundation

/// 빈병 `habitCandidates` 재연. 에이전트 CLI 는 실행하지 않는다.
enum HabitCandidateReplay {
    static let agentSkipReason = "agent command — not replayed"

    static func replay(
        candidates: [HabitCandidate],
        room: URL,
        bottle: HabitHandoffSnapshot,
        capabilities: any CapabilityLookup,
        exec: any ExecRunning
    ) throws -> [SimulationStepResult] {
        var results: [SimulationStepResult] = []
        for (index, candidate) in candidates.enumerated() {
            results.append(
                try replayOne(
                    candidate,
                    index: index,
                    room: room,
                    bottle: bottle,
                    capabilities: capabilities,
                    exec: exec
                )
            )
        }
        return results
    }

    static func passedIgnoringSkipped(_ steps: [SimulationStepResult]) -> Bool {
        steps.filter { $0.mode != .skipped }.allSatisfy(\.ok)
    }

    static func isAgentCommand(_ candidate: HabitCandidate) -> Bool {
        AgentRoomTool(rawValue: toolName(candidate)) != nil
    }

    static func toolName(_ candidate: HabitCandidate) -> String {
        let raw = candidate.argv.first ?? candidate.tool
        return URL(fileURLWithPath: raw).lastPathComponent
    }

    static func hasDryRunContract(
        _ candidate: HabitCandidate,
        capabilities: any CapabilityLookup
    ) -> Bool {
        if candidate.argv.contains("--dry-run") {
            return true
        }
        let cli = toolName(candidate)
        let command: String
        if candidate.argv.count > 1 {
            command = candidate.argv[1]
        } else {
            command = cli
        }
        return capabilities.hasDryRun(tool: cli, command: command)
    }

    static func isLinked(tool: String, in room: URL) -> Bool {
        let url = room
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(tool)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return true
        }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    private static func replayOne(
        _ candidate: HabitCandidate,
        index: Int,
        room: URL,
        bottle: HabitHandoffSnapshot,
        capabilities: any CapabilityLookup,
        exec: any ExecRunning
    ) throws -> SimulationStepResult {
        let summary = candidate.invocation
        if isAgentCommand(candidate) {
            return SimulationStepResult(
                habit: summary,
                step: index,
                mode: .skipped,
                ok: true,
                reason: agentSkipReason
            )
        }
        if hasDryRunContract(candidate, capabilities: capabilities) {
            return try executeDryRun(
                candidate,
                summary: summary,
                index: index,
                room: room,
                bottle: bottle,
                exec: exec
            )
        }
        return try compareLinkedHelp(
            candidate,
            summary: summary,
            index: index,
            room: room,
            bottle: bottle,
            exec: exec
        )
    }

    private static func executeDryRun(
        _ candidate: HabitCandidate,
        summary: String,
        index: Int,
        room: URL,
        bottle: HabitHandoffSnapshot,
        exec: any ExecRunning
    ) throws -> SimulationStepResult {
        var argv = candidate.argv
        if !argv.contains("--dry-run") {
            argv.append("--dry-run")
        }
        let output = try exec.exec(
            roomDir: room.path,
            sessionID: bottle.sessionID,
            argv: argv
        )
        let ok = output.exit == 0
        let reason: String
        if ok {
            reason = "dry-run exit 0"
        } else {
            reason = "dry-run failed (exit \(output.exit))"
        }
        return SimulationStepResult(
            habit: summary,
            step: index,
            mode: .executed,
            ok: ok,
            reason: reason
        )
    }

    private static func compareLinkedHelp(
        _ candidate: HabitCandidate,
        summary: String,
        index: Int,
        room: URL,
        bottle: HabitHandoffSnapshot,
        exec: any ExecRunning
    ) throws -> SimulationStepResult {
        let tool = toolName(candidate)
        if !isLinked(tool: tool, in: room) {
            return SimulationStepResult(
                habit: summary,
                step: index,
                mode: .compared,
                ok: false,
                reason: "tool not linked in room bin"
            )
        }
        let output = try exec.exec(
            roomDir: room.path,
            sessionID: bottle.sessionID,
            argv: [tool, "--help"]
        )
        let ok = output.exit == 0
        let reason: String
        if ok {
            reason = "bin linked and --help exit 0"
        } else {
            reason = "--help failed (exit \(output.exit))"
        }
        return SimulationStepResult(
            habit: summary,
            step: index,
            mode: .compared,
            ok: ok,
            reason: reason
        )
    }
}
