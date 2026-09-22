// parity-suppress: Headless terminal daemon and CLI tool with secondary debug GUI backlog#7a61de22-a346-4210-9668-583953b419f0
import Foundation
import RoomKit
import StateRootKit

public typealias RoomOpenPipelinePure = RoomOpenPipeline

extension RoomOpenPipeline {
    public static func dryRunSteps(successor: Bool) -> [String] {
        [
            RoomOpenStep.ledgerLookup.rawValue,
            RoomOpenStep.complianceGate.rawValue,
            RoomOpenStep.assembleFolder.rawValue,
            RoomOpenStep.credentialSeed.rawValue,
            RoomOpenStep.daemonSession.rawValue,
            successor ? RoomOpenStep.ledgerOccupySuccessor.rawValue : RoomOpenStep.ledgerOccupy.rawValue,
            RoomOpenStep.printRoomMarkdown.rawValue,
        ]
    }

    public static func bindNetwork(
        wall: NetworkWall,
        roomURL: URL,
        daemon: any DaemonSessionControlling
    ) throws -> RoomNetworkBinding {
        guard case .allow(let domains) = wall else {
            return RoomNetworkBinding(wall: wall, proxyPort: nil)
        }
        let port = try daemon.ensureNetworkProxy(
            roomDir: roomURL.path,
            allowedDomains: domains
        )
        try RoomEnvFile.applyProxy(roomURL: roomURL, wall: wall, proxyPort: port)
        return RoomNetworkBinding(wall: wall, proxyPort: port)
    }

    public static func resolvePreset(flag: String?, blueprint: String) -> RoomWallPreset {
        // 플래그가 있으면 플래그, 없으면 설계도(스펙) 값을 그대로 믿는다. open 을 toolbelt 로 강등하지 않는다.
        if let flag, let parsed = RoomWallPreset(rawValue: flag) { return parsed }
        return RoomWallPreset(rawValue: blueprint) ?? .toolbelt
    }

    public static func resolveTool(flag: String?, allowed: [String]) -> AgentRoomTool {
        if let flag, let tool = AgentRoomTool(rawValue: flag) { return tool }
        for name in allowed {
            if let tool = AgentRoomTool(rawValue: name) { return tool }
        }
        return .claude
    }

    public static func occupant(tool: AgentRoomTool) -> String {
        "agent:\(tool.rawValue)@\(hostLabel())"
    }

    public static func hostLabel() -> String {
        AgentOccupant.shortHost().lowercased()
    }

    public static func shouldJoinExistingHandover(hit: LedgerRoomHit, roomURL: URL) -> Bool {
        let bottleHandle = RoomOpenPolicy.successorHandleFromLatestBottle(in: roomURL)
            ?? RoomOpenPolicy.successorHandle(sessionID: hit.occupantSession)
        return RoomOpenPolicy.shouldJoinExistingHandover(
            handoverState: hit.handoverState,
            successorSession: hit.successorSession,
            bottleSuccessorHandle: bottleHandle
        )
    }

    public static func tenantPolicy(hit: LedgerRoomHit, environment: [String: String]) -> RoomTenantPolicy {
        let root = RoomPaths.tenantStateRoot(tenant: hit.tenant, environment: environment).path
        let slug = hit.tenant.hasPrefix("tenant:") ? String(hit.tenant.dropFirst(7)) : hit.tenant
        return RoomTenantPolicy(stateRoot: root, wikiWorld: "tenant-\(slug)")
    }

    public static func makeSpec(
        hit: LedgerRoomHit,
        preset: RoomWallPreset,
        tool: AgentRoomTool,
        environment: [String: String],
        compliance: any ComplianceChecking = TenantIsolationComplianceChecker(environment: [:]),
        selfCLIPath: String? = nil
    ) throws -> RoomAssemblySpec {
        let policy = tenantPolicy(hit: hit, environment: environment)
        let tuning: TuningValues
        do {
            tuning = try TuningStore.default(environment: environment).load()
        } catch {
            tuning = .default
        }
        var spec = ToolBudgetSpec.default(for: tool)
        spec.handoffRatio = tuning.handoffFactor
        let initialInput = initialInput(for: tool)
        let budget = Budget.compute(
            tool: tool,
            initialInput: initialInput,
            used: nil,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil,
            spec: spec
        )
        return RoomAssemblySpec(
            roomID: hit.roomID,
            slug: hit.slug,
            tenantSlug: hit.tenant,
            layoutID: hit.layoutID,
            blueprint: RoomBlueprintSnapshot(
                task: hit.task,
                verdict: hit.verdict,
                brief: hit.brief,
                toolbelt: hit.toolbelt,
                preset: preset,
                walls: RoomWallSnapshot(writePaths: hit.writePaths, network: hit.network),
                agentTools: hit.agentTools,
                workdir: hit.workdir
            ),
            tenantPolicy: policy,
            budget: RoomBudgetSnapshot(
                window: budget.window,
                trigger: budget.trigger,
                initialInput: budget.initialInput,
                reservedOutput: budget.reservedOutput,
                usable: budget.usable,
                handoffAt: budget.handoffAt
            ),
            compliance: compliance,
            environment: environment,
            homeDirectory: AppPaths.stateRoot(environment: environment).path,
            selfCLIPath: selfCLIPath
        )
    }

    public static func registerTranscript(tool: AgentRoomTool, roomURL: URL) {
        guard let path = TranscriptLocations.defaultBinding(tool: tool, roomPath: roomURL.path) else {
            return
        }
        do {
            try TranscriptRegistry.register(roomURL: roomURL, tool: tool, path: path)
        } catch {
            FileHandle.standardError.write(
                Data(("transcript register failed: \(error.localizedDescription)\n").utf8)
            )
        }
    }

    public static func verdictStatus(
        verdict: String,
        toolbelt: [String],
        excludedTools: [String],
        preset: RoomWallPreset = .toolbelt
    ) -> RoomVerdictStatus {
        guard let first = verdict.split(whereSeparator: \.isWhitespace).first.map(String.init), !first.isEmpty else {
            return RoomVerdictStatus(runnable: false, reason: "empty verdict")
        }
        guard !excludedTools.contains(first) else {
            return RoomVerdictStatus(
                runnable: false,
                reason: "verdict command excluded: \(first)"
            )
        }
        // open 방은 호스트 PATH(hostPath)를 쓰므로 toolbelt 밖 명령(swift·git)도 실행된다 — 2026-09-05 실측(!7348).
        guard preset == .open || toolbelt.contains(first) else {
            return RoomVerdictStatus(
                runnable: false,
                reason: "verdict command not in toolbelt: \(first)"
            )
        }
        return RoomVerdictStatus(runnable: true, reason: "")
    }

    public static func roomMarkdown(_ roomURL: URL) -> String {
        let url = roomURL.appendingPathComponent("ROOM.md")
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return ""
        }
    }

    public static func isOccupied(occupant: String, occupantSession: String) -> Bool {
        !occupant.isEmpty || !occupantSession.isEmpty
    }

    public static func reusedSessionID(
        occupied: Bool,
        roomPath: String,
        sessions: [RoomListedSession],
        preferRole: String? = nil,
        excluding: String? = nil
    ) -> String? {
        guard occupied else { return nil }
        let want = SessionAuthorizer.standardized(roomPath)
        let candidates = sessions.filter {
            SessionAuthorizer.standardized($0.roomDir) == want && $0.isAlive
        }
        let matching = candidates.filter { session in
            guard let excluding else { return true }
            return session.sessionID != excluding
        }
        if let preferRole, let hit = matching.first(where: { $0.sessionRole == preferRole }) {
            return hit.sessionID
        }
        return matching.first?.sessionID
    }

    public static func initialInput(for tool: AgentRoomTool) -> Int {
        let spec = ToolBudgetSpec.default(for: tool)
        for child in Mirror(reflecting: spec).children {
            if child.label == "initialInput", let value = child.value as? Int {
                return value
            }
        }
        return 0
    }
}
