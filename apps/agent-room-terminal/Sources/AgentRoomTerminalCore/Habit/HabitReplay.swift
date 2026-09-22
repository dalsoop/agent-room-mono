import Foundation

enum HabitReplay {
    static func records(room: URL, bottle: HabitHandoffSnapshot) throws -> String {
        let logURL = HabitFile.termLog(in: room)
        let log: String
        if FileManager.default.fileExists(atPath: logURL.path) {
            log = try String(contentsOf: logURL, encoding: .utf8)
        } else {
            log = ""
        }
        return log + "\n" + bottle.snapshot
    }

    static func replayCandidates(
        candidates: [HabitCandidate],
        room: URL,
        bottle: HabitHandoffSnapshot,
        capabilities: any CapabilityLookup,
        exec: any ExecRunning
    ) throws -> [SimulationStepResult] {
        try HabitCandidateReplay.replay(
            candidates: candidates,
            room: room,
            bottle: bottle,
            capabilities: capabilities,
            exec: exec
        )
    }

    static func replay(
        habits: [Habit],
        room: URL,
        bottle: HabitHandoffSnapshot,
        capabilities: any CapabilityLookup,
        exec: any ExecRunning,
        notes: DeviationNoteStore
    ) throws -> [SimulationStepResult] {
        let haystack = try records(room: room, bottle: bottle)
        var results: [SimulationStepResult] = []
        for habit in habits {
            let documented = try notes.hasNote(room: room, number: habit.number)
            for (index, step) in habit.steps.enumerated() {
                let request = ReplayStepRequest(
                    habitNumber: habit.number,
                    index: index,
                    step: step,
                    documented: documented,
                    haystack: haystack,
                    room: room,
                    sessionID: bottle.sessionID,
                    capabilities: capabilities,
                    exec: exec
                )
                results.append(try replayStep(request))
            }
        }
        return results
    }

    struct ReplayStepRequest {
        var habitNumber: Int
        var index: Int
        var step: HabitStep
        var documented: Bool
        var haystack: String
        var room: URL
        var sessionID: String
        var capabilities: any CapabilityLookup
        var exec: any ExecRunning
    }

    static func replayStep(_ request: ReplayStepRequest) throws -> SimulationStepResult {
        if request.capabilities.hasDryRun(tool: request.step.tool, command: request.step.command) {
            return try execute(
                habit: request.step.invocation,
                index: request.index,
                step: request.step,
                room: request.room,
                sessionID: request.sessionID,
                exec: request.exec
            )
        }
        return compare(
            habit: request.step.invocation,
            index: request.index,
            step: request.step,
            documented: request.documented,
            haystack: request.haystack
        )
    }

    static func execute(
        habit: String,
        index: Int,
        step: HabitStep,
        room: URL,
        sessionID: String,
        exec: any ExecRunning
    ) throws -> SimulationStepResult {
        let argv = [step.tool, step.command] + step.args + ["--dry-run"]
        let output = try exec.exec(roomDir: room.path, sessionID: sessionID, argv: argv)
        let (ok, reason) = matchPattern(step.expectedPattern, in: output.combined, executed: true)
        return SimulationStepResult(
            habit: habit,
            step: index,
            mode: .executed,
            ok: ok,
            reason: reason
        )
    }

    static func compare(
        habit: String,
        index: Int,
        step: HabitStep,
        documented: Bool,
        haystack: String
    ) -> SimulationStepResult {
        let present = haystack.contains(step.invocation)
        let (patternOK, patternReason) = matchPattern(
            step.expectedPattern,
            in: haystack,
            executed: false
        )
        if present && patternOK {
            return SimulationStepResult(
                habit: habit,
                step: index,
                mode: .compared,
                ok: true,
                reason: "record matched"
            )
        }
        if documented {
            return SimulationStepResult(
                habit: habit,
                step: index,
                mode: .compared,
                ok: true,
                reason: "documented deviation"
            )
        }
        let reason = present ? patternReason : "no record and no deviation note"
        return SimulationStepResult(
            habit: habit,
            step: index,
            mode: .compared,
            ok: false,
            reason: reason
        )
    }

    static func matchVerdict(
        context: RoomHabitContext,
        room: URL,
        bottle: HabitHandoffSnapshot,
        capabilities: any CapabilityLookup,
        exec: any ExecRunning
    ) throws -> Bool {
        let parts = context.verdict.split(separator: " ").map(String.init)
        guard let tool = parts.first else {
            return bottle.verdictOutput.isEmpty
        }
        let command = parts.count > 1 ? parts[1] : tool
        if capabilities.hasDryRun(tool: tool, command: command) {
            let argv = parts + ["--dry-run"]
            let output = try exec.exec(
                roomDir: room.path,
                sessionID: bottle.sessionID,
                argv: argv
            )
            return output.combined.contains(bottle.verdictOutput)
                || output.combined == bottle.verdictOutput
        }
        let haystack = try records(room: room, bottle: bottle)
        return haystack.contains(bottle.verdictOutput)
    }

    static func matchPattern(
        _ pattern: String?,
        in text: String,
        executed: Bool
    ) -> (Bool, String) {
        guard let pattern, !pattern.isEmpty else {
            return (true, executed ? "executed without pattern" : "record present")
        }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                return (true, "pattern matched")
            }
            return (false, "expectedPattern did not match")
        } catch {
            return (false, "invalid expectedPattern")
        }
    }
}
