import Foundation

public protocol RoomAssembling: Sendable {
    func assemble(spec: RoomAssemblySpec) throws -> RoomAssemblyResult
}

public protocol DaemonSessionControlling: Sendable {
    func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String?
    ) throws -> String
    func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String?,
        sessionRole: String?,
        columns: Int?,
        rows: Int?,
        banner: String?
    ) throws -> String
    func listSessions() throws -> [RoomListedSession]
    func closeSession(sessionID: String) throws
    func ensureNetworkProxy(roomDir: String, allowedDomains: [String]) throws -> UInt16
}

extension DaemonSessionControlling {
    public func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String?,
        sessionRole: String?,
        columns: Int?,
        rows: Int?,
        banner: String?
    ) throws -> String {
        try openSession(
            roomDir: roomDir,
            envFile: envFile,
            shell: shell,
            seatbeltProfile: seatbeltProfile
        )
    }

    public func listSessions() throws -> [RoomListedSession] {
        []
    }

    public func ensureNetworkProxy(roomDir: String, allowedDomains: [String]) throws -> UInt16 {
        throw DaemonProtocolError.requestFailed("ensureNetworkProxy not implemented")
    }
}

public protocol RoomHandoffRunning: Sendable {
    func handoff(_ request: HandoffRequest) async throws -> HandoffBottle
}

public protocol RoomSimulating: Sendable {
    func simulate(
        room: URL,
        against handoffID: String,
        by authority: LedgerAuthority
    ) async throws -> SimulationVerdict
}

public protocol HabitReading: Sendable {
    func list(in room: URL) throws -> [Habit]
}

/// 방 id 를 Core 진입점 인자로 푼다.
public struct RoomActionContext: Sendable {
    public var spec: RoomAssemblySpec
    public var roomURL: URL
    public var envFile: String
    public var shell: String
    public var seatbeltProfile: String?
    public var sessionID: String
    public var planID: String
    public var occupant: String
    public var wallMode: String
    public var authority: LedgerAuthority
    public var handoff: HandoffRequest
    public var handoffID: String

    public init(
        spec: RoomAssemblySpec,
        roomURL: URL,
        envFile: String,
        shell: String,
        seatbeltProfile: String? = nil,
        sessionID: String,
        planID: String,
        occupant: String,
        wallMode: String,
        authority: LedgerAuthority,
        handoff: HandoffRequest,
        handoffID: String
    ) {
        self.spec = spec
        self.roomURL = roomURL
        self.envFile = envFile
        self.shell = shell
        self.seatbeltProfile = seatbeltProfile
        self.sessionID = sessionID
        self.planID = planID
        self.occupant = occupant
        self.wallMode = wallMode
        self.authority = authority
        self.handoff = handoff
        self.handoffID = handoffID
    }
}

public protocol RoomActionResolving: Sendable {
    func context(for roomID: String) throws -> RoomActionContext
}

public struct LiveRoomFolder: RoomAssembling {
    public init() {}

    public func assemble(spec: RoomAssemblySpec) throws -> RoomAssemblyResult {
        try RoomFolder.assemble(spec: spec)
    }
}

public struct LiveDaemonSessions: DaemonSessionControlling {
    public var client: DaemonClient

    public init(client: DaemonClient) {
        self.client = client
    }

    public func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String?
    ) throws -> String {
        try openSession(
            roomDir: roomDir,
            envFile: envFile,
            shell: shell,
            seatbeltProfile: seatbeltProfile,
            sessionRole: nil,
            columns: nil,
            rows: nil,
            banner: nil
        )
    }

    public func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String?,
        sessionRole: String?,
        columns: Int?,
        rows: Int?,
        banner: String?
    ) throws -> String {
        let response = try client.send(.openSession(
            roomDir: roomDir,
            envFile: envFile,
            shell: shell,
            seatbeltProfile: seatbeltProfile,
            sessionRole: sessionRole,
            columns: columns,
            rows: rows,
            banner: banner
        ))
        guard response.ok else {
            throw DaemonProtocolError.requestFailed(response.error ?? "openSession failed")
        }
        guard let sessionID = response.result?["sessionID"]?.string else {
            throw DaemonProtocolError.requestFailed("openSession result missing sessionID")
        }
        return sessionID
    }

    public func listSessions() throws -> [RoomListedSession] {
        let response = try client.send(.listSessions())
        guard response.ok else { return [] }
        let items = response.result?["sessions"]?.array ?? []
        return items.compactMap { item in
            guard let id = item["sessionID"]?.string, let dir = item["roomDir"]?.string else {
                return nil
            }
            return RoomListedSession(
                sessionID: id,
                roomDir: dir,
                sessionRole: item["sessionRole"]?.string ?? RoomSessionRole.predecessor.rawValue,
                exitCode: item["exitCode"]?.int,
                recovered: item["recovered"]?.bool ?? false
            )
        }
    }

    public func ensureNetworkProxy(roomDir: String, allowedDomains: [String]) throws -> UInt16 {
        let response = try client.send(
            .ensureNetworkProxy(roomDir: roomDir, allowedDomains: allowedDomains)
        )
        guard response.ok, let port = response.result?["proxyPort"]?.int, port > 0, port <= Int(UInt16.max) else {
            throw DaemonProtocolError.requestFailed(
                response.error ?? "ensureNetworkProxy failed"
            )
        }
        return UInt16(port)
    }

    public func closeSession(sessionID: String) throws {
        let response = try client.send(.closeSession(sessionID: sessionID))
        guard response.ok else {
            throw DaemonProtocolError.requestFailed(response.error ?? "closeSession failed")
        }
    }
}

extension LedgerQueue: LedgerOccupancyRecording {}

public struct LiveHandoff: RoomHandoffRunning {
    public var service: HandoffService

    public init(service: HandoffService) {
        self.service = service
    }

    public func handoff(_ request: HandoffRequest) async throws -> HandoffBottle {
        try await service.handoff(request)
    }
}

public struct LiveSimulator: RoomSimulating {
    public var simulator: Simulator

    public init(simulator: Simulator) {
        self.simulator = simulator
    }

    public func simulate(
        room: URL,
        against handoffID: String,
        by authority: LedgerAuthority
    ) async throws -> SimulationVerdict {
        try await simulator.simulate(room: room, against: handoffID, by: authority)
    }
}

extension HabitStore: HabitReading {}

public struct DictionaryRoomActionResolver: RoomActionResolving {
    public var contexts: [String: RoomActionContext]

    public init(contexts: [String: RoomActionContext] = [:]) {
        self.contexts = contexts
    }

    public func context(for roomID: String) throws -> RoomActionContext {
        guard let found = contexts[roomID] else {
            throw RoomActionError.notAvailable(roomID)
        }
        return found
    }
}

public struct ResolverLedgerLookup: RoomLedgerLooking {
    public var resolver: any RoomActionResolving
    public var fallback: (any RoomLedgerLooking)?

    public init(resolver: any RoomActionResolving, fallback: (any RoomLedgerLooking)? = nil) {
        self.resolver = resolver
        self.fallback = fallback
    }

    public func findRoom(roomID: String, environment: [String: String]) throws -> LedgerRoomHit? {
        do {
            let ctx = try resolver.context(for: roomID)
            return ctx.toLedgerHit()
        } catch {
            return try fallback?.findRoom(roomID: roomID, environment: environment)
        }
    }
}

extension RoomActionContext {
    public func toLedgerHit() -> LedgerRoomHit {
        LedgerRoomHit(
            planID: planID,
            roomID: spec.roomID,
            slug: spec.slug,
            tenant: spec.tenantSlug,
            layoutID: spec.layoutID,
            parentRoomID: "",
            occupant: occupant,
            occupantSession: sessionID,
            wallMode: wallMode,
            successorOccupant: "",
            successorSession: "",
            handoverState: "none",
            task: spec.blueprint.task,
            verdict: spec.blueprint.verdict,
            brief: spec.blueprint.brief,
            toolbelt: spec.blueprint.toolbelt,
            preset: spec.blueprint.preset.rawValue,
            agentTools: spec.blueprint.agentTools,
            walls: LedgerRoomWalls(
                writePaths: spec.blueprint.walls.writePaths,
                network: spec.blueprint.walls.network,
                workdir: spec.blueprint.workdir
            )
        )
    }
}

public struct NullHandoffAmend: HandoffAmending {
    public init() {}

    public func amend(room: URL, handoffID: String) throws {}
}

/// GUI 가 쓰는 실제 방 명령. 픽스처 모드에서는 `RecordingRoomActions` 를 유지한다.
public struct CoreRoomActions: RoomActions {
    public var assembler: any RoomAssembling
    public var daemon: any DaemonSessionControlling
    public var ledger: any LedgerOccupancyRecording
    public var handoff: any RoomHandoffRunning
    public var simulator: any RoomSimulating
    public var habits: any HabitReading
    public var resolver: any RoomActionResolving
    public var pipeline: RoomOpenPipeline

    public init(
        assembler: any RoomAssembling,
        daemon: any DaemonSessionControlling,
        ledger: any LedgerOccupancyRecording,
        handoff: any RoomHandoffRunning,
        simulator: any RoomSimulating,
        habits: any HabitReading,
        resolver: any RoomActionResolving,
        pipeline: RoomOpenPipeline? = nil
    ) {
        self.assembler = assembler
        self.daemon = daemon
        self.ledger = ledger
        self.handoff = handoff
        self.simulator = simulator
        self.habits = habits
        self.resolver = resolver
        self.pipeline = pipeline ?? RoomOpenPipeline(
            ledgerLookup: ResolverLedgerLookup(resolver: resolver),
            complianceChecker: TenantIsolationComplianceChecker(environment: [:]),
            assembler: assembler,
            credentialSeeder: LiveCredentialSeeder(),
            daemon: daemon,
            ledgerOccupancy: ledger
        )
    }

    public static func live(
        client: DaemonClient,
        resolver: any RoomActionResolving,
        ledger: LedgerQueue = LedgerQueue(),
        habits: HabitStore = HabitStore()
    ) -> CoreRoomActions {
        let handoffService = HandoffService(
            ledger: HandoffLedgerQueue(queue: ledger),
            daemon: DaemonClientSnapshot(client: client)
        )
        let simulator = Simulator(
            store: habits,
            capabilities: MapCapabilityLookup(),
            exec: DaemonClientExec(client: client),
            ledger: ledger,
            handoff: NullHandoffAmend()
        )
        let assembler = LiveRoomFolder()
        let daemon = LiveDaemonSessions(client: client)
        let pipeline = RoomOpenPipeline(
            ledgerLookup: ResolverLedgerLookup(resolver: resolver, fallback: LiveRoomLedgerLookup()),
            complianceChecker: TenantIsolationComplianceChecker(environment: [:]),
            assembler: assembler,
            credentialSeeder: LiveCredentialSeeder(),
            daemon: daemon,
            ledgerOccupancy: ledger
        )
        return CoreRoomActions(
            assembler: assembler,
            daemon: daemon,
            ledger: ledger,
            handoff: LiveHandoff(service: handoffService),
            simulator: LiveSimulator(simulator: simulator),
            habits: habits,
            resolver: resolver,
            pipeline: pipeline
        )
    }

    public func openRoom(id: String) async throws {
        let env: [String: String]
        do {
            let ctx = try resolver.context(for: id)
            env = ctx.spec.environment
        } catch {
            env = ProcessInfo.processInfo.environment
        }
        let input = RoomOpenPipelineInput(
            roomID: id,
            environment: env
        )
        _ = try await pipeline.open(input)
    }

    public func closeRoom(id: String) async throws {
        let ctx = try resolver.context(for: id)
        try daemon.closeSession(sessionID: ctx.sessionID)
        RoomLifecycle.close(roomURL: ctx.roomURL)
        try await ledger.recordClose(
            plan: ctx.planID,
            workdir: ctx.roomURL.path,
            by: ctx.authority
        )
    }

    public func handoff(roomID: String) async throws {
        let ctx = try resolver.context(for: roomID)
        _ = try await self.handoff.handoff(ctx.handoff)
    }

    public func simulate(roomID: String) async throws {
        let ctx = try resolver.context(for: roomID)
        _ = try await simulator.simulate(
            room: ctx.roomURL,
            against: ctx.handoffID,
            by: ctx.authority
        )
    }

    public func showHabits(roomID: String) async throws {
        let ctx = try resolver.context(for: roomID)
        _ = try habits.list(in: ctx.roomURL)
    }
}
