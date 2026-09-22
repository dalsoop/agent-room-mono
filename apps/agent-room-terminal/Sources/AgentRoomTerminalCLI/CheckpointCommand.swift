import Foundation
import AgentRoomTerminalCore

enum CheckpointCommand {
    static let usageText = """
        usage: checkpoint create <room-id> [--id <id>] [--desc "…"] [--json]
               checkpoint rollback <room-id> --to <checkpoint-id> [--json]
               checkpoint list <room-id> [--json]
        """

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }

        let isJSON = CLIArgs.takeJSON(&rest)
        guard let sub = rest.first else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        let tail = Array(rest.dropFirst())

        do {
            switch sub {
            case "create":
                try handleCreate(tail, isJSON: isJSON)
            case "rollback":
                try handleRollback(tail, isJSON: isJSON)
            case "list":
                try handleList(tail, isJSON: isJSON)
            default:
                CLIIO.fail(usageText, code: CLIExit.usage)
            }
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    private static func handleCreate(_ args: [String], isJSON: Bool) throws {
        let rest = args
        let ckptID = CLIArgs.value("--id", in: rest)
        let desc = CLIArgs.value("--desc", in: rest)
        let positionals = CLIArgs.dropFlags(rest, flags: ["--json"], valueFlags: ["--id", "--desc"])

        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail("usage: checkpoint create <room-id> [--id <id>] [--desc \"…\"]", code: CLIExit.usage)
        }

        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)

        let checkpoint = try RoomCheckpointManager.shared.createCheckpoint(
            roomURL: roomURL,
            checkpointID: ckptID,
            description: desc
        )

        if isJSON {
            CLIIO.printOK(checkpoint)
        } else {
            CLIIO.printLine("체크포인트 생성 완료: \(checkpoint.id) (파일 \(checkpoint.fileCount)개, \(checkpoint.totalSizeBytes) 바이트)")
        }
    }

    private static func handleRollback(_ args: [String], isJSON: Bool) throws {
        let rest = args
        guard let targetID = CLIArgs.value("--to", in: rest) else {
            CLIIO.fail("usage: checkpoint rollback <room-id> --to <checkpoint-id>", code: CLIExit.usage)
        }
        let positionals = CLIArgs.dropFlags(rest, flags: ["--json"], valueFlags: ["--to"])

        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail("usage: checkpoint rollback <room-id> --to <checkpoint-id>", code: CLIExit.usage)
        }

        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)

        try RoomCheckpointManager.shared.rollback(roomURL: roomURL, to: targetID)

        if isJSON {
            CLIIO.printOKObject([
                "roomID": roomID,
                "rolledBackTo": targetID,
                "status": "success",
            ])
        } else {
            CLIIO.printLine("방 \(roomID) work/ 폴더를 체크포인트 \(targetID) 로 롤백 완료했습니다.")
        }
    }

    private static func handleList(_ args: [String], isJSON: Bool) throws {
        let positionals = CLIArgs.dropFlags(args, flags: ["--json"], valueFlags: [])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail("usage: checkpoint list <room-id>", code: CLIExit.usage)
        }

        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)

        let list = try RoomCheckpointManager.shared.listCheckpoints(roomURL: roomURL)

        if isJSON {
            CLIIO.printOK(list)
        } else {
            if list.isEmpty {
                CLIIO.printLine("등록된 체크포인트가 없습니다.")
            } else {
                for item in list {
                    let desc = item.description.map { " - \($0)" } ?? ""
                    CLIIO.printLine("[\(item.id)] \(item.createdAt) (파일 \(item.fileCount)개)\(desc)")
                }
            }
        }
    }
}

enum RunsCommand {
    static let usageText = """
        usage: runs list <room-id> [--json]
               runs show <room-id> <run-id> [--json]
        """

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            CLIIO.printLine(usageText)
            exit(CLIExit.ok)
        }

        let isJSON = CLIArgs.takeJSON(&rest)
        guard let sub = rest.first else {
            CLIIO.fail(usageText, code: CLIExit.usage)
        }
        let tail = Array(rest.dropFirst())

        do {
            switch sub {
            case "list":
                try handleList(tail, isJSON: isJSON)
            case "show":
                try handleShow(tail, isJSON: isJSON)
            default:
                CLIIO.fail(usageText, code: CLIExit.usage)
            }
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    private static func handleList(_ args: [String], isJSON: Bool) throws {
        let positionals = CLIArgs.dropFlags(args, flags: ["--json"], valueFlags: [])
        guard let roomID = positionals.first, !roomID.isEmpty else {
            CLIIO.fail("usage: runs list <room-id>", code: CLIExit.usage)
        }

        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)

        let runs = try RoomGuardedRunner.shared.listRuns(in: roomURL)

        if isJSON {
            CLIIO.printOK(runs)
        } else {
            if runs.isEmpty {
                CLIIO.printLine("보존된 실행 기록이 없습니다.")
            } else {
                for r in runs {
                    let rollbackStr = r.rolledBack ? " [ROLLED BACK]" : ""
                    CLIIO.printLine("[\(r.runID)] verdict: \(r.verdict.rawValue)\(rollbackStr) (\(r.argv.joined(separator: " ")))")
                }
            }
        }
    }

    private static func handleShow(_ args: [String], isJSON: Bool) throws {
        let positionals = CLIArgs.dropFlags(args, flags: ["--json"], valueFlags: [])
        guard positionals.count >= 2 else {
            CLIIO.fail("usage: runs show <room-id> <run-id>", code: CLIExit.usage)
        }
        let roomID = positionals[0]
        let runID = positionals[1]

        let env = ProcessInfo.processInfo.environment
        let roomURL = try requireRoom(roomID: roomID, environment: env)

        guard let run = try RoomGuardedRunner.shared.getRun(in: roomURL, runID: runID) else {
            CLIIO.fail("실행 기록을 찾을 수 없습니다: \(runID)")
        }

        if isJSON {
            CLIIO.printOK(run)
        } else {
            CLIIO.printLine("""
            Run: \(run.runID)
            Room: \(run.roomID)
            Verdict: \(run.verdict.rawValue) (exitCode: \(run.exitCode), rolledBack: \(run.rolledBack))
            Command: \(run.argv.joined(separator: " "))
            Duration: \(run.durationMs)ms
            Pre-checkpoint: \(run.checkpointIDBefore)
            Post-checkpoint: \(run.checkpointIDAfter ?? "none")
            Violations: \(run.violations.isEmpty ? "none" : run.violations.joined(separator: ", "))
            Passed Verifications: \(run.passedVerifications.isEmpty ? "none" : run.passedVerifications.joined(separator: ", "))
            """)
        }
    }
}
