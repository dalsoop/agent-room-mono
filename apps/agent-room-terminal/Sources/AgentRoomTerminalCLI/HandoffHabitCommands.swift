import Foundation
import AgentRoomTerminalCore

enum HandoffCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        let execute = CLIArgs.takeExecute(&rest)
        let json = CLIArgs.takeJSON(&rest)
        let note = CLIArgs.value("--note", in: rest) ?? ""
        let amend = CLIArgs.value("--amend", in: rest)
        let show = CLIArgs.value("--show", in: rest)
        let positionals = CLIArgs.dropFlags(
            rest,
            flags: ["--json"],
            valueFlags: ["--note", "--amend", "--show"]
        )
        guard let roomID = positionals.first else {
            CLIIO.fail(
                "usage: handoff <room-id> --note \"…\" [--amend <id>] [--execute] | handoff <room-id> --show <id>",
                code: CLIExit.usage
            )
        }
        if let show {
            showBottle(roomID: roomID, bottleID: show, json: json)
            return
        }
        if !execute {
            CLIIO.printOKObject(DryRunPlan.object(
                command: "handoff",
                roomID: roomID,
                steps: amend == nil
                    ? ["write-bottle", "ledger-digest", "occupy-successor"]
                    : ["amend-bottle"]
            ))
            return
        }
        CLIAsync.run {
            try await executeHandoff(roomID: roomID, note: note, amend: amend)
        }
    }

    static func showBottle(roomID: String, bottleID: String, json: Bool) {
        do {
            let folder = try requireRoom(
                roomID: roomID,
                environment: ProcessInfo.processInfo.environment
            )
            let bottle = try HandoffService.readBottle(id: bottleID, in: folder)
            if json {
                CLIIO.printOK(bottle)
                return
            }
            CLIIO.printLine(bottle.markdownSummary())
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func executeHandoff(roomID: String, note: String, amend: String?) async throws {
        let env = ProcessInfo.processInfo.environment
        let folder = try requireRoom(roomID: roomID, environment: env)
        let client = DaemonCommand.commandRoomClient()
        let session = try sessionID(roomURL: folder, client: client) ?? ""
        let document = try RoomDocument.load(from: folder)
        let budgetState = try BudgetCommand.loadBudget(roomID: roomID)
        let budget = try budgetFromObject(budgetState)
        let service = makeService(client: client)
        let authority = LedgerAuthority.commandRoom(sessionID: session, seatedRoomID: roomID)
        if let amend {
            let bottle = try await service.amend(
                bottleID: amend,
                roomURL: folder,
                note: note,
                sessionID: session,
                budget: budget
            )
            CLIIO.printOK(bottle)
            return
        }
        let planID = UUID(uuidString: document.layoutId) != nil ? document.layoutId : UUID().uuidString
        let request = HandoffRequest(
            roomID: roomID,
            roomURL: folder,
            planID: planID,
            note: note,
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
        let bottle = try await service.handoff(request)
        CLIIO.printOK(bottle)
    }

    static func makeService(client: DaemonClient) -> HandoffService {
        HandoffService(
            ledger: HandoffLedgerQueue(queue: RoomQueue()),
            daemon: DaemonClientSnapshot(client: client)
        )
    }
}

enum HabitCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        let execute = CLIArgs.takeExecute(&rest)
        let sub = rest.first ?? "list"
        let tail = Array(rest.dropFirst())
        do {
            switch sub {
            case "list":
                try list(tail)
            case "note":
                try note(tail)
            case "promote":
                try promote(tail, execute: execute)
            default:
                CLIIO.fail("usage: habit list|note|promote <room-id> …", code: CLIExit.usage)
            }
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func list(_ args: [String]) throws {
        let candidatesOnly = args.contains("--candidates")
        let roomID = args.first { !$0.hasPrefix("--") } ?? ""
        guard !roomID.isEmpty else {
            CLIIO.fail("usage: habit list <room-id> [--candidates]", code: CLIExit.usage)
        }
        let folder = try requireRoom(roomID: roomID, environment: ProcessInfo.processInfo.environment)
        let habits = try HabitStore().list(in: folder)
        let candidates = try HabitCandidateStore.list(in: folder)
        if candidatesOnly {
            CLIIO.printOK(candidates)
            return
        }
        CLIIO.printOK(HabitListPayload(habits: habits, candidates: candidates))
    }

    static func note(_ args: [String]) throws {
        let roomID = args.first ?? ""
        let number = Int(CLIArgs.value("--deviated", in: args) ?? "") ?? 0
        let reason = CLIArgs.value("--reason", in: args) ?? ""
        guard !roomID.isEmpty, number > 0 else {
            CLIIO.fail("usage: habit note <room-id> --deviated <n> --reason \"…\"",
                       code: CLIExit.usage)
        }
        let folder = try requireRoom(roomID: roomID, environment: ProcessInfo.processInfo.environment)
        let recorded = try DeviationNoteStore().record(
            room: folder,
            number: number,
            reason: reason
        )
        CLIIO.printOKObject([
            "number": recorded.number,
            "reason": recorded.reason,
            "url": recorded.url.path,
        ])
    }

    static func promote(_ args: [String], execute: Bool) throws {
        let fromCandidates = args.contains("--from-candidates")
        guard let roomID = args.first, !roomID.hasPrefix("--") else {
            CLIIO.fail(
                "usage: habit promote <room-id> <number>|--from-candidates [--execute]",
                code: CLIExit.usage
            )
        }
        if fromCandidates {
            if !execute {
                CLIIO.printOKObject(DryRunPlan.object(
                    command: "habit promote",
                    roomID: roomID,
                    steps: ["promote-candidates"]
                ))
                return
            }
            let folder = try requireRoom(
                roomID: roomID, environment: ProcessInfo.processInfo.environment
            )
            let created = try HabitCandidateStore.promote(in: folder, store: HabitStore())
            CLIIO.printOKObject([
                "promoted": created.count,
                "numbers": created.map(\.number),
            ])
            return
        }
        let number = Int(args.dropFirst().first ?? "") ?? 0
        if !execute {
            CLIIO.printOKObject(DryRunPlan.object(
                command: "habit promote",
                roomID: roomID,
                steps: ["wiki-candidate", "wiki-promotion-publish"]
            ))
            return
        }
        let env = ProcessInfo.processInfo.environment
        let folder = try requireRoom(roomID: roomID, environment: env)
        let tuning = loadTuning(environment: env)
        let promoter = HabitPromoter(
            store: HabitStore(tuning: tuning.habit),
            wiki: WikiCommandKitPublisher(environment: env),
            tuning: tuning.habit,
            environment: env
        )
        let habit = try promoter.promote(room: folder, number: number)
        CLIIO.printOK(habit)
    }
}

enum SimulateCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        _ = CLIArgs.takeJSON(&rest)
        let against = CLIArgs.value("--against", in: rest)
        let positionals = CLIArgs.dropFlags(rest, flags: [], valueFlags: ["--against"])
        guard let roomID = positionals.first, let bottle = against else {
            CLIIO.fail("usage: simulate <room-id> --against <bottle-id> --json", code: CLIExit.usage)
        }
        CLIAsync.run {
            try await execute(roomID: roomID, bottle: bottle)
        }
    }

    static func execute(roomID: String, bottle: String) async throws {
        let env = ProcessInfo.processInfo.environment
        let folder = try requireRoom(roomID: roomID, environment: env)
        let client = DaemonCommand.commandRoomClient()
        let tuning = loadTuning(environment: env)
        let simulator = Simulator(
            store: HabitStore(tuning: tuning.habit),
            capabilities: JSONCapabilityLookup(),
            exec: DaemonClientExec(client: client),
            ledger: NoopLedgerHandover(),
            handoff: CLIHandoffAmend(),
            tuning: tuning.habit
        )
        let authority = LedgerAuthority.commandRoom(sessionID: "cli-sim", seatedRoomID: roomID)
        let verdict = try await simulator.simulate(room: folder, against: bottle, by: authority)
        var payload: [String: Any] = [
            "passed": verdict.passed,
            "verdictMatched": verdict.verdictMatched,
            "reason": verdict.reason,
            "steps": verdict.steps.map { step in
                [
                    "habit": step.habit,
                    "step": step.step,
                    "mode": step.mode.rawValue,
                    "ok": step.ok,
                    "reason": step.reason,
                ] as [String: Any]
            },
        ]
        if verdict.reason.isEmpty {
            payload.removeValue(forKey: "reason")
        }
        CLIIO.printOKObject(payload)
    }
}

struct CLIHandoffAmend: HandoffAmending {
    func amend(room: URL, handoffID: String) throws {
        _ = try DeviationNoteStore().writeAmendRequest(room: room, handoffID: handoffID)
    }
}

func loadTuning(environment: [String: String]) -> TuningValues {
    do {
        return try TuningStore.default(environment: environment).load()
    } catch {
        return .default
    }
}

func budgetFromObject(_ object: [String: Any]) throws -> BudgetState {
    BudgetState(
        window: object["window"] as? Int ?? 0,
        trigger: object["trigger"] as? Double ?? 0,
        initialInput: object["initialInput"] as? Int ?? 0,
        reservedOutput: object["reservedOutput"] as? Int ?? 0,
        usable: object["usable"] as? Int ?? 0,
        used: object["used"] as? Int,
        handoffAt: object["handoffAt"] as? Int ?? 0,
        elapsedMinutes: object["elapsedMinutes"] as? Int,
        estimatedWorkMinutes: object["estimatedWorkMinutes"] as? Int,
        state: BudgetPhase(rawValue: object["state"] as? String ?? "unknown") ?? .unknown
    )
}
