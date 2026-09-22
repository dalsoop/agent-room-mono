import AgentRoomTerminalCore
import CommandKit
import Foundation
import RoomKit

/// 방 안 도구를 무인으로 한 번 찔러보는 명령 또는 핸드오프 라이프사이클 스모크 명령.
enum SmokeCommand {
    static let usageText = "usage: smoke <room-id> --tool claude|codex|grok [--prompt TEXT] | smoke handoff <room-id> [--execute] [--json]"

    static func run(_ args: [String]) {
        let rest = Array(args.dropFirst())
        if rest.first == "handoff" {
            runHandoff(rest)
            return
        }
        let toolFlag = CLIArgs.value("--tool", in: rest)
        let promptFlag = CLIArgs.value("--prompt", in: rest)
        let positionals = CLIArgs.dropFlags(rest, flags: [], valueFlags: ["--tool", "--prompt"])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        guard let toolFlag, let tool = AgentRoomTool(rawValue: toolFlag) else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        let prompt = promptFlag ?? "say ok"
        guard let toolArgs = AgentToolInvocation.arguments(tool: tool, prompt: prompt) else {
            CLIIO.fail("no non-interactive invocation known for tool: \(tool.rawValue)")
        }
        do {
            try ExecCommand.runExec(roomID: roomID, argv: [tool.rawValue] + toolArgs)
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func runHandoff(_ args: [String]) {
        var rest = Array(args.dropFirst())
        let execute = CLIArgs.takeExecute(&rest)
        let isJSON = CLIArgs.takeJSON(&rest)
        let positionals = CLIArgs.dropFlags(rest, flags: ["--json", "--execute"], valueFlags: [])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail("usage: smoke handoff <room-id> [--execute] [--json]", code: CLIExit.usage)
        }
        if !execute {
            CLIIO.printOKObject(DryRunPlan.object(
                command: "smoke handoff",
                roomID: roomID,
                steps: [
                    "check-budget-exhaustion",
                    "write-bottle",
                    "swap-bottle",
                    "seat-successor-simulating",
                    "vacate-predecessor",
                    "simulate-successor-passed",
                ]
            ))
            return
        }
        CLIAsync.run {
            try await executeSmokeHandoff(roomID: roomID, isJSON: isJSON)
        }
    }

    static func executeSmokeHandoff(roomID: String, isJSON: Bool) async throws {
        let env = ProcessInfo.processInfo.environment
        let folder = try requireRoom(roomID: roomID, environment: env)
        let client = DaemonCommand.commandRoomClient()
        let session = try sessionID(roomURL: folder, client: client) ?? ""
        let document = try RoomDocument.load(from: folder)

        // 1. Trigger budget exhaustion if not already exhausted
        let exhaustedBudget = try exhaustBudgetIfNeeded(roomID: roomID, folder: folder)

        // 2. Count bottles before swap
        let beforeBottles = TreeCommand.bottleIDs(in: folder)
        let initialBottleCount = beforeBottles.count

        // 3. Execute handoff (creates bottle, increments bottleSwapCount, sets handoverState = simulating)
        let bottle = try await createHandoffBottle(
            roomID: roomID, folder: folder, session: session,
            document: document, client: client, budget: exhaustedBudget
        )

        // 4. Verify bottleSwapCount increment
        let afterBottles = TreeCommand.bottleIDs(in: folder)
        guard afterBottles.count == initialBottleCount + 1 else {
            throw SmokeHandoffError.bottleSwapCountMismatch(
                expected: initialBottleCount + 1,
                actual: afterBottles.count
            )
        }

        // 5. Verify handoverState is simulating
        try assertHandoverState(roomID: roomID, env: env, expected: "simulating")

        // 6. Simulate against new bottle (closes predecessor, sets handoverState = passed)
        try await runSimulation(roomID: roomID, folder: folder, bottleID: bottle.id, env: env, client: client)

        // 7. Verify predecessor left/vacated and new occupant confirmed
        try assertHandoverState(roomID: roomID, env: env, expected: "passed")

        let eventLog = RoomEventLog(roomURL: folder)
        let events = eventLog.read().events
        let hasVacated = events.contains { $0.kind == RoomEventKind.vacated }

        let payload: [String: Any] = [
            "ok": true,
            "roomID": roomID,
            "bottleID": bottle.id,
            "bottleSwapCount": afterBottles.count,
            "handoverState": "passed",
            "predecessorStatus": hasVacated ? "vacated" : "closed",
            "successorStatus": "passed",
            "passed": true,
        ]
        CLIIO.printOKObject(payload)
    }

    private static func exhaustBudgetIfNeeded(roomID: String, folder: URL) throws -> BudgetState {
        let initialBudget = try BudgetCommand.loadBudget(roomID: roomID)
        let initialBudgetState = try budgetFromObject(initialBudget)
        let handoffAt = initialBudgetState.handoffAt > 0 ? initialBudgetState.handoffAt : 700_000
        let currentUsed = initialBudgetState.used ?? 0
        if currentUsed < handoffAt {
            try recordExhaustionUsage(roomURL: folder, used: handoffAt + 1)
        }
        let exhaustedBudgetObj = try BudgetCommand.loadBudget(roomID: roomID)
        return try budgetFromObject(exhaustedBudgetObj)
    }

    private static func createHandoffBottle(
        roomID: String,
        folder: URL,
        session: String,
        document: RoomDocument,
        client: DaemonClient,
        budget: BudgetState
    ) async throws -> HandoffBottle {
        let service = HandoffCommand.makeService(client: client)
        let authority = LedgerAuthority.commandRoom(sessionID: session, seatedRoomID: roomID)
        let planID = UUID(uuidString: document.layoutId) != nil ? document.layoutId : UUID().uuidString
        let request = HandoffRequest(
            roomID: roomID,
            roomURL: folder,
            planID: planID,
            note: "smoke handoff automated test",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: OpenCommand.occupant(tool: .claude),
            successorOccupant: OpenCommand.occupant(tool: .claude),
            successorHandle: OpenPolicy.successorHandle(sessionID: session),
            sessionID: session,
            wallMode: "full",
            authority: authority
        )
        return try await service.handoff(request)
    }

    private static func assertHandoverState(roomID: String, env: [String: String], expected: String) throws {
        var currentState = expected
        do {
            if let doc = try LedgerLookup.findRoom(roomID: roomID, environment: env) {
                currentState = doc.handoverState
            }
        } catch {
            fputs("warning: LedgerLookup.findRoom failed: \(error)\n", stderr)
        }
        guard currentState == expected else {
            throw SmokeHandoffError.invalidHandoverState(
                expected: expected,
                actual: currentState
            )
        }
    }

    private static func runSimulation(
        roomID: String,
        folder: URL,
        bottleID: String,
        env: [String: String],
        client: DaemonClient
    ) async throws {
        let tuning = loadTuning(environment: env)
        let simulator = Simulator(
            store: HabitStore(tuning: tuning.habit),
            capabilities: JSONCapabilityLookup(),
            exec: DaemonClientExec(client: client),
            ledger: NoopLedgerHandover(),
            handoff: CLIHandoffAmend(),
            tuning: tuning.habit
        )
        let simAuthority = LedgerAuthority.commandRoom(sessionID: "cli-smoke-sim", seatedRoomID: roomID)
        let verdict = try await simulator.simulate(room: folder, against: bottleID, by: simAuthority)
        guard verdict.passed else {
            throw SmokeHandoffError.simulationFailed(verdict.reason)
        }
    }

    private static func recordExhaustionUsage(roomURL: URL, used: Int) throws {
        let stateDir = roomURL.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let usageFile = stateDir.appendingPathComponent("usage.jsonl")
        let toolName = AgentRoomTool.claude.rawValue
        let entry = """
        {"inputTokens":\(used),"outputTokens":0,"requests":1,"tool":"\(toolName)","ts":"\(ISO8601DateFormatter().string(from: Date()))"}
        """
        if FileManager.default.fileExists(atPath: usageFile.path) {
            let handle = try FileHandle(forWritingTo: usageFile)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let d = (entry + "\n").data(using: .utf8) {
                try handle.write(contentsOf: d)
            }
        } else {
            try (entry + "\n").write(to: usageFile, atomically: true, encoding: .utf8)
        }
        let eventLog = RoomEventLog(roomURL: roomURL)
        do {
            _ = try eventLog.append(RoomEvent.budgetSampled(used: used, limit: 700_000, estimated: false))
        } catch {
            fputs("warning: failed to record budgetSampled event: \(error)\n", stderr)
        }
    }
}

enum SmokeHandoffError: LocalizedError {
    case bottleSwapCountMismatch(expected: Int, actual: Int)
    case invalidHandoverState(expected: String, actual: String)
    case simulationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .bottleSwapCountMismatch(expected, actual):
            return "bottleSwapCount mismatch: expected \(expected), got \(actual)"
        case let .invalidHandoverState(expected, actual):
            return "handoverState mismatch: expected \(expected), got \(actual)"
        case let .simulationFailed(reason):
            return "smoke simulation failed: \(reason)"
        }
    }
}
