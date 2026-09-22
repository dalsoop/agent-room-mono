import Foundation
import RoomKit
import StateRootKit

public struct RoomOpenPipeline: Sendable {
    public var ledgerLookup: any RoomLedgerLooking
    public var complianceChecker: any ComplianceChecking
    public var assembler: any RoomAssembling
    public var credentialSeeder: any CredentialSeeding
    public var daemon: any DaemonSessionControlling
    public var ledgerOccupancy: any LedgerOccupancyRecording

    public init(
        ledgerLookup: any RoomLedgerLooking,
        complianceChecker: any ComplianceChecking,
        assembler: any RoomAssembling,
        credentialSeeder: any CredentialSeeding,
        daemon: any DaemonSessionControlling,
        ledgerOccupancy: (any LedgerOccupancyRecording)? = nil
    ) {
        self.ledgerLookup = ledgerLookup
        self.complianceChecker = complianceChecker
        self.assembler = assembler
        self.credentialSeeder = credentialSeeder
        self.daemon = daemon
        self.ledgerOccupancy = ledgerOccupancy ?? NoopLedgerOccupancy()
    }

    public static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        client: DaemonClient? = nil
    ) -> RoomOpenPipeline {
        let daemonClient = client ?? DaemonClient(
            socketURL: AppPaths.daemonSocketURL(environment: environment),
            spawnIfMissing: false,
            connectAttempts: 8,
            authority: SessionAuthorizer.commandRoomAuthority
        )
        return RoomOpenPipeline(
            ledgerLookup: LiveRoomLedgerLookup(environment: environment),
            complianceChecker: TenantIsolationComplianceChecker(environment: environment),
            assembler: LiveRoomFolder(),
            credentialSeeder: LiveCredentialSeeder(),
            daemon: LiveDaemonSessions(client: daemonClient)
        )
    }

    public func loadHit(_ input: RoomOpenPipelineInput) throws -> LedgerRoomHit {
        if let specURL = input.specURL {
            return try LedgerRoomHit.decode(specData: try Data(contentsOf: specURL))
        }
        if let found = try ledgerLookup.findRoom(roomID: input.roomID, environment: input.environment) {
            return found
        }
        throw LedgerLookupError.notInLedger(input.roomID)
    }

    public func open(_ input: RoomOpenPipelineInput) async throws -> RoomOpenPipelineResult {
        // 1. spec-load (with ledger-lookup fallback)
        let hit = try loadHit(input)

        // 2. compliance-gate & resolution
        let preset = Self.resolvePreset(flag: input.presetFlag, blueprint: hit.preset)
        let tool = Self.resolveTool(flag: input.toolFlag, allowed: hit.agentTools)

        // 3. assemble-folder
        let spec = try Self.makeSpec(
            hit: hit,
            preset: preset,
            tool: tool,
            environment: input.environment,
            compliance: complianceChecker,
            selfCLIPath: input.selfCLIPath
        )
        let assembled = try assembler.assemble(spec: spec)
        _ = try RoomEventLog(roomURL: assembled.roomURL).append(RoomEvent.assembled(by: "agent-room-terminal"))

        // 4. credential-seed
        let credentialSeed = credentialSeeder.seed(tool: tool, roomURL: assembled.roomURL)

        // 5. daemon-session
        let bannerText = RoomBriefing.text(spec: spec)
        let occupantString = input.requestedOccupant ?? Self.occupant(tool: tool)
        let opened: RoomOpenedSession
        let profile: String?
        do {
            (opened, profile) = try establishDaemonSession(
                hit: hit,
                assembled: assembled,
                preset: preset,
                input: input,
                occupantString: occupantString,
                bannerText: bannerText
            )
        } catch {
            _ = credentialSeeder.unseedAll(roomURL: assembled.roomURL)
            throw error
        }

        // 6. ledger-occupy(-successor)
        var finalOpened = opened
        try await performOccupancy(
            hit: hit,
            roomURL: assembled.roomURL,
            tool: tool,
            occupantString: occupantString,
            opened: &finalOpened
        )

        // 7. print-ROOM.md
        Self.registerTranscript(tool: tool, roomURL: assembled.roomURL)
        let verdict = Self.verdictStatus(
            verdict: hit.verdict,
            toolbelt: hit.toolbelt,
            excludedTools: assembled.excludedTools,
            preset: preset
        )
        let roomMD = Self.roomMarkdown(assembled.roomURL)

        return RoomOpenPipelineResult(
            hit: hit,
            preset: preset,
            tool: tool,
            spec: spec,
            assembled: assembled,
            opened: finalOpened,
            seatbeltProfile: profile,
            sessionID: finalOpened.sessionID,
            occupant: occupantString,
            wallMode: "full",
            credentialSeed: credentialSeed,
            verdict: verdict,
            roomMarkdown: roomMD,
            bannerText: bannerText
        )
    }

    private struct SessionContext {
        let hit: LedgerRoomHit
        let assembled: RoomAssemblyResult
        let preset: RoomWallPreset
        let profile: String?
        let seatbelt: Bool
        let live: [RoomListedSession]
        let network: RoomNetworkBinding
        let columns: Int?
        let rows: Int?
        let banner: String?
    }

    private func establishDaemonSession(
        hit: LedgerRoomHit,
        assembled: RoomAssemblyResult,
        preset: RoomWallPreset,
        input: RoomOpenPipelineInput,
        occupantString: String,
        bannerText: String
    ) throws -> (RoomOpenedSession, String?) {
        let binding = try Self.bindNetwork(wall: hit.network, roomURL: assembled.roomURL, daemon: daemon)
        let profile = RoomOpenPolicy.seatbeltProfile(
            preset: preset,
            roomPath: assembled.roomURL.path,
            writePaths: hit.writePaths,
            network: hit.network,
            agentTools: hit.agentTools,
            proxyPort: binding.proxyPort,
            workdir: hit.workdir
        )
        let seatbelt = profile != nil
        let live = try daemon.listSessions()

        let asSuccessor = RoomOpenPolicy.shouldOpenSuccessor(
            flag: input.successorFlag,
            handoverState: hit.handoverState,
            occupant: hit.occupant,
            successorOccupant: hit.successorOccupant,
            requestedOccupant: occupantString
        )

        let ctx = SessionContext(
            hit: hit,
            assembled: assembled,
            preset: preset,
            profile: profile,
            seatbelt: seatbelt,
            live: live,
            network: binding,
            columns: input.columns,
            rows: input.rows,
            banner: bannerText
        )

        let opened: RoomOpenedSession
        if asSuccessor {
            opened = try openSuccessor(ctx)
        } else {
            opened = try openPredecessor(ctx)
        }
        return (opened, profile)
    }


    private func openSuccessor(_ ctx: SessionContext) throws -> RoomOpenedSession {
        let predecessor = predecessorSessionID(hit: ctx.hit, roomURL: ctx.assembled.roomURL, live: ctx.live)
        if let existing = Self.reusedSessionID(
            occupied: true,
            roomPath: ctx.assembled.roomURL.path,
            sessions: ctx.live,
            preferRole: RoomSessionRole.successor.rawValue,
            excluding: predecessor
        ) {
            return RoomOpenedSession(
                sessionID: existing,
                reused: true,
                seatbelt: ctx.seatbelt,
                sessionRole: RoomSessionRole.successor.rawValue,
                predecessorSession: predecessor,
                network: ctx.network
            )
        }
        let session = try daemon.openSession(
            roomDir: ctx.assembled.roomURL.path,
            envFile: ctx.assembled.roomURL.appendingPathComponent("env").path,
            shell: ctx.preset == .open ? "zsh" : "zsh -r",
            seatbeltProfile: ctx.profile,
            sessionRole: RoomSessionRole.successor.rawValue,
            columns: ctx.columns,
            rows: ctx.rows,
            banner: ctx.banner
        )
        return RoomOpenedSession(
            sessionID: session,
            reused: false,
            seatbelt: ctx.seatbelt,
            sessionRole: RoomSessionRole.successor.rawValue,
            predecessorSession: predecessor,
            network: ctx.network
        )
    }

    private func openPredecessor(_ ctx: SessionContext) throws -> RoomOpenedSession {
        if let existing = reuseIfOccupied(hit: ctx.hit, roomURL: ctx.assembled.roomURL, live: ctx.live) {
            return RoomOpenedSession(
                sessionID: existing,
                reused: true,
                seatbelt: ctx.seatbelt,
                sessionRole: RoomSessionRole.predecessor.rawValue,
                network: ctx.network
            )
        }
        let session = try daemon.openSession(
            roomDir: ctx.assembled.roomURL.path,
            envFile: ctx.assembled.roomURL.appendingPathComponent("env").path,
            shell: ctx.preset == .open ? "zsh" : "zsh -r",
            seatbeltProfile: ctx.profile,
            sessionRole: RoomSessionRole.predecessor.rawValue,
            columns: ctx.columns,
            rows: ctx.rows,
            banner: ctx.banner
        )
        return RoomOpenedSession(
            sessionID: session,
            reused: false,
            seatbelt: ctx.seatbelt,
            sessionRole: RoomSessionRole.predecessor.rawValue,
            network: ctx.network
        )
    }

    private func predecessorSessionID(
        hit: LedgerRoomHit,
        roomURL: URL,
        live: [RoomListedSession]
    ) -> String? {
        if !hit.occupantSession.isEmpty { return hit.occupantSession }
        return Self.reusedSessionID(
            occupied: true,
            roomPath: roomURL.path,
            sessions: live,
            preferRole: RoomSessionRole.predecessor.rawValue
        )
    }

    private func reuseIfOccupied(
        hit: LedgerRoomHit,
        roomURL: URL,
        live: [RoomListedSession]
    ) -> String? {
        let occupied = Self.isOccupied(
            occupant: hit.occupant,
            occupantSession: hit.occupantSession
        )
        return Self.reusedSessionID(
            occupied: occupied,
            roomPath: roomURL.path,
            sessions: live,
            preferRole: RoomSessionRole.predecessor.rawValue
        )
    }
}

