import Foundation
import AgentRoomTerminalCore

enum OpenCommand {
    static let openMark = "개방"
    static let usageText = """
        usage: open [<room-id>] [--spec <path>] [--preset readOnly|toolbelt|open] \
        [--tool …] [--successor] [--execute]
        usage: open --attach-session <sessionID> [--room <id>]
        """

    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        let execute = CLIArgs.takeExecute(&rest)
        let successorFlag = rest.contains("--successor")
        rest.removeAll { $0 == "--successor" }
        if let sessionID = CLIArgs.value("--attach-session", in: rest) {
            runAttach(sessionID: sessionID, rest: rest)
            return
        }
        let presetFlag = CLIArgs.value("--preset", in: rest)
        let toolFlag = CLIArgs.value("--tool", in: rest)
        let specFlag = CLIArgs.value("--spec", in: rest)
        let positionals = CLIArgs.dropFlags(
            rest,
            flags: ["--json", "--successor"],
            valueFlags: ["--preset", "--tool", "--spec", "--attach-session", "--room"]
        )
        let specURL = specFlag.map { URL(fileURLWithPath: $0) }
        guard let roomID = positionals.first ?? specURL?.deletingPathExtension().lastPathComponent, !roomID.isEmpty else {
            CLIIO.fail(Self.usageText, code: CLIExit.usage)
        }
        if !execute {
            var plan = dryPlan(
                roomID: roomID,
                specURL: specURL,
                preset: presetFlag,
                tool: toolFlag,
                successor: successorFlag
            )
            plan["note"] = "dry-run — 실제로 열려면 --execute"
            CLIIO.printOKObject(plan)
            if !args.contains("--json") {
                FileHandle.standardError.write(Data("dry-run — 실제로 열려면 --execute\n".utf8))
            }
            return
        }
        CLIAsync.run {
            try await executeOpen(
                roomID: roomID,
                specURL: specURL,
                presetFlag: presetFlag,
                toolFlag: toolFlag,
                successorFlag: successorFlag
            )
        }
    }

    static func dryPlan(
        roomID: String,
        specURL: URL? = nil,
        preset: String?,
        tool: String?,
        successor: Bool = false
    ) -> [String: Any] {
        var plan = DryRunPlan.object(
            command: "open",
            roomID: roomID,
            steps: RoomOpenPipeline.dryRunSteps(successor: successor)
        )
        if let specURL { plan["spec"] = specURL.path }
        if let preset { plan["preset"] = preset }
        if let tool { plan["tool"] = tool }
        if successor { plan["successor"] = true }
        if preset == "open" { plan["openMark"] = openMark }
        return plan
    }

    static func executeOpen(
        roomID: String,
        specURL: URL? = nil,
        presetFlag: String?,
        toolFlag: String?,
        successorFlag: Bool = false
    ) async throws {
        _ = try await DaemonCommand.start()
        let pipeline = RoomOpenPipeline.live()
        let input = RoomOpenPipelineInput(
            roomID: roomID,
            specURL: specURL,
            presetFlag: presetFlag,
            toolFlag: toolFlag,
            successorFlag: successorFlag
        )
        let result = try await pipeline.open(input)
        if result.credentialSeed == .failed {
            FileHandle.standardError.write(
                Data(("credential seed failed — keychain 값을 못 읽었다. \(result.tool.rawValue) 는 방 안에서 로그인 안 될 수 있다\n").utf8)
            )
        }
        if !result.verdict.runnable {
            FileHandle.standardError.write(
                Data(("verdict not runnable: \(result.verdict.reason)\n").utf8)
            )
        }
        CLIIO.printOKObject(openResult(OpenResultInput(
            hit: result.hit,
            preset: result.preset,
            tool: result.tool,
            assembled: result.assembled,
            opened: result.opened,
            wallMode: result.wallMode,
            verdict: result.verdict,
            markdown: result.roomMarkdown,
            credentialSeed: result.credentialSeed
        )))
    }

    /// 예산 게이지가 unknown 으로 남지 않게, 도구의 전사 위치를 방에 등록한다(있는 도구만).
    static func registerTranscript(tool: AgentRoomTool, roomURL: URL) {
        RoomOpenPipeline.registerTranscript(tool: tool, roomURL: roomURL)
    }

    /// verdict 명령이 방에서 돌 수 없으면 stderr 에 한 줄 경고를 남긴다(열기는 막지 않는다).
    static func warnIfVerdictNotRunnable(
        hit: LedgerRoomHit,
        excludedTools: [String],
        preset: RoomWallPreset
    ) -> OpenPolicy.VerdictStatus {
        let verdict = RoomOpenPipeline.verdictStatus(
            verdict: hit.verdict,
            toolbelt: hit.toolbelt,
            excludedTools: excludedTools,
            preset: preset
        )
        if !verdict.runnable {
            FileHandle.standardError.write(
                Data(("verdict not runnable: \(verdict.reason)\n").utf8)
            )
        }
        return verdict
    }

    static func resolvePreset(flag: String?, blueprint: String) -> RoomWallPreset {
        RoomOpenPipeline.resolvePreset(flag: flag, blueprint: blueprint)
    }

    static func resolveTool(flag: String?, allowed: [String]) -> AgentRoomTool {
        RoomOpenPipeline.resolveTool(flag: flag, allowed: allowed)
    }

    static func occupant(tool: AgentRoomTool) -> String {
        RoomOpenPipeline.occupant(tool: tool)
    }

    /// simulating 원장에 이미 앉은 후임이면 occupy --successor 를 다시 치지 않는다.
    static func shouldJoinExistingHandover(hit: LedgerRoomHit, roomURL: URL) -> Bool {
        RoomOpenPipeline.shouldJoinExistingHandover(hit: hit, roomURL: roomURL)
    }

    /// 원장 신원 규약 `agent:<tool>@<host 첫 라벨>`. 호스트 이름의 첫 점 앞 조각을 소문자로.
    static func hostLabel() -> String {
        RoomOpenPipeline.hostLabel()
    }

    static func makeSpec(
        hit: LedgerRoomHit,
        preset: RoomWallPreset,
        tool: AgentRoomTool,
        environment: [String: String]
    ) throws -> RoomAssemblySpec {
        try RoomOpenPipeline.makeSpec(hit: hit, preset: preset, tool: tool, environment: environment)
    }

    static func runAttach(sessionID: String, rest: [String]) {
        let roomFlag = CLIArgs.value("--room", in: rest)
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? DurableAppLayout.defaultHomeDirectory.path
        do {
            let result = try SessionAttach.run(SessionAttachRequest(
                sessionID: sessionID,
                roomID: roomFlag,
                environment: env,
                homeDirectory: home
            ))
            CLIIO.printOKObject(result.jsonObject)
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    static func tenantPolicy(hit: LedgerRoomHit, environment: [String: String]) -> RoomTenantPolicy {
        RoomOpenPipeline.tenantPolicy(hit: hit, environment: environment)
    }
}
