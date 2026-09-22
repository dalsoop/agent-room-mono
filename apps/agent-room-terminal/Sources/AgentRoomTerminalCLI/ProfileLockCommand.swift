import Foundation
import AgentRoomTerminalCore
import RoomKit

enum ProfileLockCommand {
    static let usageText = """
        usage: profile-lock <room-id> [--trace-file <path>] [--from-candidate] \
        [--tenant <slug>] [--apply] [--json]

        성공한 실행의 파일/네트워크/프로세스 발자국을 관찰하여 방 벽 초안을 생성하고 \
        테넌트 미준수 위반 지점을 진단합니다.
        """

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        guard !rest.contains("--help") && !rest.contains("-h") else {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }

        let isJSON = CLIArgs.takeJSON(&rest)
        let apply = CLIArgs.takeFlag("--apply", from: &rest)
        let fromCandidate = CLIArgs.takeFlag("--from-candidate", from: &rest)
        let traceFilePath = CLIArgs.value("--trace-file", in: rest)
        let tenantSlug = CLIArgs.value("--tenant", in: rest)

        let positionals = CLIArgs.dropFlags(
            rest,
            flags: ["--json", "--apply", "--from-candidate"],
            valueFlags: ["--trace-file", "--tenant"]
        )

        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }

        execute(
            roomID: roomID,
            traceFilePath: traceFilePath,
            fromCandidate: fromCandidate,
            tenantSlug: tenantSlug,
            apply: apply,
            isJSON: isJSON
        )
    }

    private static func execute(
        roomID: String,
        traceFilePath: String?,
        fromCandidate: Bool,
        tenantSlug: String?,
        apply: Bool,
        isJSON: Bool
    ) {
        do {
            let env = ProcessInfo.processInfo.environment
            let roomURL = try requireRoom(roomID: roomID, environment: env)
            let footprint = try resolveFootprint(
                traceFilePath: traceFilePath,
                fromCandidate: fromCandidate,
                roomURL: roomURL,
                roomID: roomID
            )
            let tenantBoundary: String? = tenantSlug.map { "~/.tenants/" + $0 }
            let draft = ProfileThenLock.generateDraft(
                footprint: footprint,
                roomURL: roomURL,
                tenantBoundary: tenantBoundary
            )
            try saveDraftIfRequested(draft: draft, apply: apply, roomURL: roomURL)
            outputDraft(draft: draft, isJSON: isJSON)
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    private static func resolveFootprint(
        traceFilePath: String?,
        fromCandidate: Bool,
        roomURL: URL,
        roomID: String
    ) throws -> ExecutionFootprint {
        if let traceFilePath {
            return try parseTraceFile(at: traceFilePath)
        }
        if fromCandidate {
            return try loadFootprintFromCandidate(roomURL: roomURL, roomID: roomID)
        }
        return try loadDefaultFootprint(roomURL: roomURL)
    }

    private static func parseTraceFile(at traceFilePath: String) throws -> ExecutionFootprint {
        let fileURL = URL(fileURLWithPath: traceFilePath)
        guard FileManager().fileExists(atPath: fileURL.path) else {
            CLIIO.fail("Trace file not found: \(traceFilePath)", code: CLIExit.usage)
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        if content.contains("UID") && content.contains("COMM") {
            return TraceLogParser.parseOpensnoop(lines: lines, argv: ["trace-file"], exitCode: 0)
        }
        return TraceLogParser.parseFsUsage(lines: lines, argv: ["trace-file"], exitCode: 0)
    }

    private static func loadFootprintFromCandidate(roomURL: URL, roomID: String) throws -> ExecutionFootprint {
        let candidates = try HabitCandidateStore.recent(in: roomURL, limit: 1)
        guard let candidate = candidates.first else {
            CLIIO.fail("No habit candidate recorded in room: \(roomID)", code: CLIExit.usage)
        }
        return makeCandidateFootprint(candidate: candidate, roomURL: roomURL)
    }

    private static func loadDefaultFootprint(roomURL: URL) throws -> ExecutionFootprint {
        let candidates = try HabitCandidateStore.recent(in: roomURL, limit: 1)
        if let candidate = candidates.first {
            return makeCandidateFootprint(candidate: candidate, roomURL: roomURL)
        }
        return ExecutionFootprint(
            argv: ["session"],
            exitCode: 0,
            fileWrites: [roomURL.appendingPathComponent("work").path],
            childProcesses: ["git"],
            workingDirectory: roomURL.path
        )
    }

    private static func makeCandidateFootprint(candidate: HabitCandidate, roomURL: URL) -> ExecutionFootprint {
        ExecutionFootprint(
            argv: candidate.argv,
            exitCode: candidate.exitCode,
            durationMs: candidate.durationMs,
            fileReads: [],
            fileWrites: [roomURL.appendingPathComponent("work").path],
            networkOutbound: [],
            childProcesses: candidate.argv.first.map { [$0] } ?? [],
            workingDirectory: roomURL.path
        )
    }

    private static func saveDraftIfRequested(draft: RoomWallDraft, apply: Bool, roomURL: URL) throws {
        guard apply else { return }
        let draftURL = roomURL.appendingPathComponent("walls.draft.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(draft)
        try data.write(to: draftURL, options: .atomic)
    }

    private static func outputDraft(draft: RoomWallDraft, isJSON: Bool) {
        if isJSON {
            CLIIO.printOK(draft)
        } else {
            CLIIO.printLine(draft.markdownReport())
        }
    }
}
