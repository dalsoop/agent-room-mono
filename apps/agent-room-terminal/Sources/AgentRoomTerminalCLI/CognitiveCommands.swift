import Foundation
import RoomKit
import AgentRoomTerminalCore
import CommandKit

// MARK: - PrecomputeCommand (선제적 가계산 잠금)

enum PrecomputeCommand {
    static let usageText = """
        usage: precompute <room-id> --targets <path1,path2> --lines <N> --sec <S> \
        [--imports <m1,m2>] [--tier trivial|standard|architectural] [--predecessors <id1,id2>] [--execute]
        """

    struct ParsedInput {
        let roomID: String
        let execute: Bool
        let precompute: RoomPrecompute
    }

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }

        let input = parseInput(&rest)
        if !input.execute {
            emitDryRun(input.precompute)
            return
        }

        executePrecompute(input.precompute)
    }

    private static func parseInput(_ rest: inout [String]) -> ParsedInput {
        let execute = CLIArgs.takeExecute(&rest)
        _ = CLIArgs.takeJSON(&rest)

        let tierRaw = CLIArgs.value("--tier", in: rest) ?? "standard"
        let targetsRaw = CLIArgs.value("--targets", in: rest) ?? ""
        let linesRaw = CLIArgs.value("--lines", in: rest) ?? "0"
        let secRaw = CLIArgs.value("--sec", in: rest) ?? "60"
        let importsRaw = CLIArgs.value("--imports", in: rest) ?? ""
        let predecessorsRaw = CLIArgs.value("--predecessors", in: rest) ?? ""

        let positionals = CLIArgs.dropFlags(
            rest,
            flags: ["--execute", "--json"],
            valueFlags: ["--tier", "--targets", "--lines", "--sec", "--imports", "--predecessors"]
        )

        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }

        let targets = targetsRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !targets.isEmpty else {
            CLIIO.fail("precompute requires at least one target file (--targets <path1,path2>)", code: CLIExit.usage)
        }

        let estimate = CognitiveEstimate(
            lines: Int(linesRaw) ?? 0,
            durationSec: Int(secRaw) ?? 60,
            declaredImports: importsRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )

        let precompute = RoomPrecompute(
            roomID: roomID,
            tenantID: "tenant:default",
            tier: CognitiveTier(rawValue: tierRaw) ?? .standard,
            targets: targets,
            estimate: estimate,
            predecessorRoomIDs: predecessorsRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )

        return ParsedInput(roomID: roomID, execute: execute, precompute: precompute)
    }

    private static func emitDryRun(_ p: RoomPrecompute) {
        CLIIO.printOKObject([
            "roomID": p.roomID,
            "tier": p.tier.rawValue,
            "targets": p.targets,
            "estimatedLines": p.estimatedLines,
            "estimatedDurationSec": p.estimatedDurationSec,
            "declaredImports": p.declaredImports,
            "predecessorRoomIDs": p.predecessorRoomIDs,
            "commitmentHash": p.commitmentHash,
            "dryRun": true,
            "note": "dry-run — 실제로 잠그려면 --execute"
        ])
    }

    private static func executePrecompute(_ p: RoomPrecompute) {
        do {
            let env = ProcessInfo.processInfo.environment
            let roomURL = try requireRoom(roomID: p.roomID, environment: env)
            let layout = RoomVaultLayout(roomURL: roomURL)
            let ledger = RoomCognitiveLedger()
            let recorded = try ledger.recordPrecompute(p, in: layout)

            CLIIO.printOKObject([
                "roomID": recorded.roomID,
                "tier": recorded.tier.rawValue,
                "targets": recorded.targets,
                "estimatedLines": recorded.estimatedLines,
                "estimatedDurationSec": recorded.estimatedDurationSec,
                "declaredImports": recorded.declaredImports,
                "predecessorRoomIDs": recorded.predecessorRoomIDs,
                "commitmentHash": recorded.commitmentHash,
                "recorded": true
            ])
        } catch {
            CLIIO.fail("failed to record precompute: \(error.localizedDescription)")
        }
    }
}

// MARK: - DeltaCommand (기계적 실측 오차 평가)

enum DeltaCommand {
    static let usageText = "usage: delta <room-id> [--break-glass] [--reason <text>] [--execute]"

    struct ParsedInput {
        let roomID: String
        let execute: Bool
        let isBreakGlass: Bool
        let reason: String?
    }

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }

        let input = parseInput(&rest)
        evaluateAndEmit(input)
    }

    private static func parseInput(_ rest: inout [String]) -> ParsedInput {
        let execute = CLIArgs.takeExecute(&rest)
        _ = CLIArgs.takeJSON(&rest)
        let isBreakGlass = CLIArgs.takeFlag("--break-glass", from: &rest)
        let reason = CLIArgs.value("--reason", in: rest)

        let positionals = CLIArgs.dropFlags(
            rest,
            flags: ["--execute", "--json", "--break-glass"],
            valueFlags: ["--reason"]
        )

        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }

        return ParsedInput(
            roomID: roomID,
            execute: execute,
            isBreakGlass: isBreakGlass,
            reason: reason
        )
    }

    private static func evaluateAndEmit(_ input: ParsedInput) {
        do {
            let env = ProcessInfo.processInfo.environment
            let roomURL = try requireRoom(roomID: input.roomID, environment: env)
            let layout = RoomVaultLayout(roomURL: roomURL)
            let ledger = RoomCognitiveLedger()

            guard let precompute = ledger.readPrecompute(in: layout) else {
                CLIIO.fail("no precompute found for room \(input.roomID). Precompute commitment must precede execution.")
            }

            let measurement = measureRoomExecution(
                roomURL: roomURL,
                isBreakGlass: input.isBreakGlass,
                reason: input.reason
            )

            let probe = RoomMechanicalProbe()
            let delta = probe.evaluate(precompute: precompute, measurement: measurement)

            if !input.execute {
                emitDryRun(delta)
                return
            }

            let recorded = try ledger.recordDelta(delta, in: layout)
            emitRecorded(recorded)
        } catch {
            CLIIO.fail("failed to evaluate delta: \(error.localizedDescription)")
        }
    }

    private static func emitDryRun(_ d: RoomDelta) {
        CLIIO.printOKObject([
            "roomID": d.roomID,
            "commitmentHash": d.commitmentHash,
            "driftScore": d.driftScore,
            "verdict": d.verdict.rawValue,
            "actualTouchedFiles": d.actualTouchedFiles,
            "actualLinesAdded": d.actualLinesAdded,
            "actualLinesDeleted": d.actualLinesDeleted,
            "unauthorizedImports": d.unauthorizedImports,
            "requiresFalsificationSynapse": d.requiresFalsificationSynapse,
            "isBreakGlass": d.isBreakGlass,
            "dryRun": true,
            "note": "dry-run — 실제로 기록하려면 --execute"
        ])
    }

    private static func emitRecorded(_ d: RoomDelta) {
        CLIIO.printOKObject([
            "roomID": d.roomID,
            "commitmentHash": d.commitmentHash,
            "driftScore": d.driftScore,
            "verdict": d.verdict.rawValue,
            "actualTouchedFiles": d.actualTouchedFiles,
            "actualLinesAdded": d.actualLinesAdded,
            "actualLinesDeleted": d.actualLinesDeleted,
            "unauthorizedImports": d.unauthorizedImports,
            "requiresFalsificationSynapse": d.requiresFalsificationSynapse,
            "isBreakGlass": d.isBreakGlass,
            "recorded": true
        ])
    }

    static func measureRoomExecution(
        roomURL: URL,
        isBreakGlass: Bool,
        reason: String?
    ) -> RoomMechanicalProbe.Measurement {
        let diffNumstat = runGitCommand(["diff", "--numstat"], in: roomURL)
        let diffNameOnly = runGitCommand(["diff", "--name-only"], in: roomURL)

        var touchedFiles = diffNameOnly.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var linesAdded = 0
        var linesDeleted = 0

        for line in diffNumstat.split(separator: "\n") {
            let tokens = line.split(separator: "\t")
            guard tokens.count >= 2 else { continue }
            linesAdded += Int(tokens[0]) ?? 0
            linesDeleted += Int(tokens[1]) ?? 0
        }

        if touchedFiles.isEmpty {
            let statusOutput = runGitCommand(["status", "--porcelain"], in: roomURL)
            for line in statusOutput.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.count > 3 else { continue }
                let file = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !touchedFiles.contains(file) {
                    touchedFiles.append(file)
                }
            }
        }

        return RoomMechanicalProbe.Measurement(
            actualTouchedFiles: touchedFiles,
            actualLinesAdded: linesAdded,
            actualLinesDeleted: linesDeleted,
            actualDurationSec: 30.0,
            detectedImports: [],
            isBreakGlass: isBreakGlass,
            breakGlassReason: reason
        )
    }

    private static func runGitCommand(_ args: [String], in dir: URL) -> String {
        let safeResult = SafeProcessRunner.run(
            "/usr/bin/git",
            args
            workingDirectory: dir,
        )
        let data = Data(safeResult.stdout.utf8)
        watchdog.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - SynapsesCommand (시냅스 토폴로지 및 쓰기 마스크 조회)

enum SynapsesCommand {
    static let usageText = "usage: synapses <room-id> [--mask]"

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }
        let showMask = CLIArgs.takeFlag("--mask", from: &rest)
        _ = CLIArgs.takeJSON(&rest)

        let positionals = CLIArgs.dropFlags(rest, flags: ["--json", "--mask"], valueFlags: [])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }

        inspectSynapses(roomID: roomID, showMask: showMask)
    }

    private static func inspectSynapses(roomID: String, showMask: Bool) {
        do {
            let env = ProcessInfo.processInfo.environment
            let roomURL = try requireRoom(roomID: roomID, environment: env)
            let layout = RoomVaultLayout(roomURL: roomURL)
            let ledger = RoomCognitiveLedger()

            if showMask {
                let mask = ledger.buildSynapseMask(for: roomID, tenant: "tenant:default", environment: env)
                CLIIO.printOKObject([
                    "roomID": roomID,
                    "maskedFilePaths": mask.maskedFilePaths,
                    "blockingRoomIDs": mask.blockingRoomIDs
                ])
            } else {
                let edges = ledger.readSynapses(in: layout)
                CLIIO.printOKObject([
                    "roomID": roomID,
                    "synapses": edges.map { [
                        "id": $0.id,
                        "source": $0.sourceRoomID,
                        "target": $0.targetRoomID,
                        "kind": $0.kind.rawValue,
                        "weight": $0.weight,
                        "summary": $0.summary
                    ] }
                ])
            }
        } catch {
            CLIIO.fail("failed to inspect synapses: \(error.localizedDescription)")
        }
    }
}
