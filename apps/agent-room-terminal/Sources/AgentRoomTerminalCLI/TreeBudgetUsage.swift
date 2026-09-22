import Foundation
import AgentRoomTerminalCore

enum TreeCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        _ = CLIArgs.takeJSON(&rest)
        let tenant = CLIArgs.value("--tenant", in: rest)
        do {
            CLIIO.printOKObject(["rooms": try buildTree(tenant: tenant)])
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func buildTree(tenant: String?) throws -> [[String: Any]] {
        let env = ProcessInfo.processInfo.environment
        let folders = try RoomFolderLocator.allRooms(tenant: tenant, environment: env)
        var rows: [[String: Any]] = []
        for folder in folders {
            rows.append(try row(for: folder, environment: env))
        }
        return rows
    }

    static func row(for folder: URL, environment: [String: String]) throws -> [String: Any] {
        let document = try RoomDocument.load(from: folder)
        let bottles = bottleIDs(in: folder)
        let usage = usageTotals(in: folder)
        let budget = Budget.compute(
            tool: .claude,
            initialInput: document.budget.initialInput,
            used: usage.used == 0 ? nil : usage.used,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
        let hit: LedgerRoomHit?
        do {
            hit = try LedgerLookup.findRoom(roomID: document.id, environment: environment)
        } catch {
            FileHandle.standardError.write(
                Data(("tree ledger skip: \(error.localizedDescription)\n").utf8)
            )
            hit = nil
        }
        let bottleSwapCount = max(bottles.count, hit?.bottleSwapCount ?? 0)
        let handoverState = hit?.handoverState ?? (bottles.isEmpty ? "none" : "simulating")
        var result: [String: Any] = [
            "id": document.id,
            "slug": document.slug,
            "tenant": document.tenant,
            "path": folder.path,
            "preset": document.preset.rawValue,
            "excludedTools": document.excludedTools,
            "handoffChain": bottles,
            "bottleSwapCount": bottleSwapCount,
            "budget": budgetObject(budget),
            "occupant": hit?.occupant ?? "",
            "successorOccupant": hit?.successorOccupant ?? "",
            "handoverState": handoverState,
            "wallMode": hit?.wallMode ?? "full",
        ]
        if isLegacyLayout(folder: folder, roomID: document.id) {
            result["legacy"] = true
        }
        return result
    }

    static func bottleIDs(in folder: URL) -> [String] {
        let dir = folder.appendingPathComponent("handoff", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: dir.path)
        } catch {
            names = []
        }
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}

enum BudgetCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        _ = CLIArgs.takeJSON(&rest)
        guard let roomID = rest.first else {
            CLIIO.fail("usage: budget <room-id> --json", code: CLIExit.usage)
        }
        do {
            CLIIO.printOKObject(try loadBudget(roomID: roomID))
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func loadBudget(roomID: String) throws -> [String: Any] {
        let env = ProcessInfo.processInfo.environment
        let folder = try requireRoom(roomID: roomID, environment: env)
        let document = try RoomDocument.load(from: folder)
        let usage = try UsageLedger.inRoom(folder).totals()
        let tool = AgentRoomTool(rawValue: roomTool(in: folder)) ?? .claude
        let tuning = try TuningStore.default(environment: env).load()
        var spec = ToolBudgetSpec.default(for: tool)
        spec.handoffRatio = tuning.handoffFactor
        // 0 은 "0 사용"이다. unknown 은 측정 소스(전사 바인딩·usage.jsonl 줄)가 하나도
        // 없을 때만 — GUI(RoomTreeSource)와 같은 기준. (실측 2026-09-04: 0 == unknown 오판)
        let used: Int? = usage.requests == 0 ? nil : usage.used
        let state = Budget.compute(
            tool: tool,
            initialInput: document.budget.initialInput,
            used: used,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil,
            spec: spec
        )
        return budgetObject(state)
    }
}

enum UsageCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        _ = CLIArgs.takeJSON(&rest)
        guard let roomID = rest.first else {
            CLIIO.fail("usage: usage <room-id> --json", code: CLIExit.usage)
        }
        do {
            let folder = try requireRoom(roomID: roomID, environment: ProcessInfo.processInfo.environment)
            let totals = try UsageLedger.inRoom(folder).totals()
            let entries = try UsageLedger.inRoom(folder).load()
            CLIIO.printOKObject([
                "inputTokens": totals.inputTokens,
                "outputTokens": totals.outputTokens,
                "requests": totals.requests,
                "used": totals.used,
                "entries": entries.map { entry in
                    [
                        "ts": entry.ts,
                        "tool": entry.tool,
                        "inputTokens": entry.inputTokens,
                        "outputTokens": entry.outputTokens,
                        "requests": entry.requests,
                    ]
                },
            ])
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }
}

func usageTotals(in folder: URL) -> UsageTotals {
    do {
        return try UsageLedger.inRoom(folder).totals()
    } catch {
        return UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
    }
}

func roomTool(in folder: URL) -> String {
    do {
        return try RoomEnvReaderAdapter.tool(in: folder)
    } catch {
        return ""
    }
}

func budgetObject(_ state: BudgetState) -> [String: Any] {
    var object: [String: Any] = [
        "window": state.window,
        "trigger": state.trigger,
        "initialInput": state.initialInput,
        "reservedOutput": state.reservedOutput,
        "usable": state.usable,
        "handoffAt": state.handoffAt,
        "state": state.state.rawValue,
    ]
    if let used = state.used { object["used"] = used }
    if let elapsed = state.elapsedMinutes { object["elapsedMinutes"] = elapsed }
    if let estimated = state.estimatedWorkMinutes { object["estimatedWorkMinutes"] = estimated }
    return object
}

/// 레거시 2-depth 경로(`rooms/<layoutID>/<slug>`)인지 판별한다.
/// 정본 경로는 `rooms/<roomID>`이며, 부모 디렉터리 이름이 roomID 와 같으면 정본이다.
func isLegacyLayout(folder: URL, roomID: String) -> Bool {
    let parent = folder.deletingLastPathComponent()
    let grandparent = parent.deletingLastPathComponent()
    if parent.lastPathComponent == "rooms" {
        return folder.lastPathComponent.lowercased() != roomID.lowercased()
    }
    if grandparent.lastPathComponent == "rooms" {
        return true
    }
    return false
}

enum RoomEnvReaderAdapter {
    static func tool(in room: URL) throws -> String {
        let url = room.appendingPathComponent("env")
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("ROOM_PRESET=") { continue }
        }
        return "claude"
    }
}
