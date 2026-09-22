import Foundation
import os
import XCTest
@testable import AgentRoomTerminalCore

private struct AllowAll: ComplianceChecking, Sendable {
    func isCompliant(cli: String) throws -> Bool { true }
}

private struct OpenSessionCall: Equatable {
    var roomDir: String
    var envFile: String
    var shell: String
    var seatbeltProfile: String?
}

private struct OccupancyCall: Equatable {
    var plan: String
    var room: String
    var occupant: String
    var session: String
    var wallMode: String
    var authoritySession: String
}

private struct CloseLedgerCall: Equatable {
    var plan: String
    var workdir: String
    var seatedRoomID: String
}

private struct SimulateCall: Equatable {
    var room: URL
    var handoffID: String
    var seatedRoomID: String
}

private final class SpyAssembler: RoomAssembling, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())
    var roomIDs: [String] { lock.withLock { $0 } }

    func assemble(spec: RoomAssemblySpec) throws -> RoomAssemblyResult {
        lock.withLock { $0.append(spec.roomID) }
        return RoomAssemblyResult(
            roomURL: URL(fileURLWithPath: "/tmp/rooms/\(spec.roomID)"),
            excludedTools: ["bad-cli"],
            linkedTools: ["good-cli"]
        )
    }
}

private struct DaemonSpyState: Sendable {
    var nextSession = "session-opened"
    var opens: [OpenSessionCall] = []
    var closes: [String] = []
}

private final class SpyDaemon: DaemonSessionControlling, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: DaemonSpyState())

    var nextSession: String { lock.withLock { $0.nextSession } }
    var opens: [OpenSessionCall] { lock.withLock { $0.opens } }
    var closes: [String] { lock.withLock { $0.closes } }

    func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String?
    ) throws -> String {
        lock.withLock { state in
            state.opens.append(OpenSessionCall(
                roomDir: roomDir,
                envFile: envFile,
                shell: shell,
                seatbeltProfile: seatbeltProfile
            ))
            return state.nextSession
        }
    }

    func closeSession(sessionID: String) throws {
        lock.withLock { $0.closes.append(sessionID) }
    }
}

private final class OccupancyLedgerSpy: LedgerOccupancyRecording, Sendable {
    private let occLock = OSAllocatedUnfairLock(initialState: [OccupancyCall]())
    private let closeLock = OSAllocatedUnfairLock(initialState: [CloseLedgerCall]())

    var occupancies: [OccupancyCall] { occLock.withLock { $0 } }
    var closes: [CloseLedgerCall] { closeLock.withLock { $0 } }

    func recordOccupancy(
        plan: String,
        room: String,
        occupant: String,
        session: String,
        wallMode: String,
        by authority: LedgerAuthority
    ) async throws {
        occLock.withLock {
            $0.append(OccupancyCall(
                plan: plan,
                room: room,
                occupant: occupant,
                session: session,
                wallMode: wallMode,
                authoritySession: authority.sessionID
            ))
        }
    }

    func recordClose(
        plan: String,
        workdir: String,
        by authority: LedgerAuthority
    ) async throws {
        closeLock.withLock {
            $0.append(CloseLedgerCall(
                plan: plan,
                workdir: workdir,
                seatedRoomID: authority.seatedRoomID
            ))
        }
    }
}

private final class SpyHandoff: RoomHandoffRunning, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [HandoffRequest]())
    var requests: [HandoffRequest] { lock.withLock { $0 } }

    func handoff(_ request: HandoffRequest) async throws -> HandoffBottle {
        lock.withLock { $0.append(request) }
        return HandoffBottle(
            id: "bottle-1",
            roomID: request.roomID,
            predecessor: request.predecessor,
            tool: request.tool.rawValue,
            note: request.note,
            budget: request.budget,
            createdAt: "2026-01-01T00:00:00Z",
            remainingWork: request.note
        )
    }
}

private final class SpySimulator: RoomSimulating, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [SimulateCall]())
    var calls: [SimulateCall] { lock.withLock { $0 } }

    func simulate(
        room: URL,
        against handoffID: String,
        by authority: LedgerAuthority
    ) async throws -> SimulationVerdict {
        lock.withLock {
            $0.append(SimulateCall(
                room: room,
                handoffID: handoffID,
                seatedRoomID: authority.seatedRoomID
            ))
        }
        return SimulationVerdict(passed: true, steps: [], verdictMatched: true)
    }
}

private final class SpyHabits: HabitReading, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [URL]())
    var rooms: [URL] { lock.withLock { $0 } }

    func list(in room: URL) throws -> [Habit] {
        lock.withLock { $0.append(room) }
        return []
    }
}

final class CoreRoomActionsTests: XCTestCase {
    func testOpenCallsAssembleOpenSessionAndOccupancy() async throws {
        let spies = Spies()
        let ctx = makeContext()
        let actions = spies.actions(ctx)
        try await actions.openRoom(id: ctx.spec.roomID)
        XCTAssertEqual(spies.assembler.roomIDs, [ctx.spec.roomID])
        XCTAssertEqual(spies.daemon.opens, [
            OpenSessionCall(
                roomDir: ctx.roomURL.path,
                envFile: ctx.envFile,
                shell: ctx.shell,
                seatbeltProfile: ctx.seatbeltProfile
            ),
        ])
        let eventLog = RoomEventLog(roomURL: ctx.roomURL)
        let events = eventLog.read().events
        XCTAssertTrue(events.contains { $0.kind == RoomEventKind.occupied })
    }

    func testGoldenComparisonCLIAndGUIProduceIdenticalSpecProfileAndOccupancy() async throws {
        let spiesCLI = Spies()
        let spiesGUI = Spies()
        let ctx = makeContext()

        // 1. GUI path: CoreRoomActions.openRoom
        let guiActions = spiesGUI.actions(ctx)
        try await guiActions.openRoom(id: ctx.spec.roomID)

        // 2. CLI path: RoomOpenPipeline.open
        let cliPipeline = RoomOpenPipeline(
            ledgerLookup: ResolverLedgerLookup(resolver: DictionaryRoomActionResolver(contexts: [ctx.spec.roomID: ctx])),
            complianceChecker: AllowAll(),
            assembler: spiesCLI.assembler,
            credentialSeeder: LiveCredentialSeeder(),
            daemon: spiesCLI.daemon,
            ledgerOccupancy: spiesCLI.ledger
        )
        let cliInput = RoomOpenPipelineInput(
            roomID: ctx.spec.roomID,
            environment: ctx.spec.environment
        )
        _ = try await cliPipeline.open(cliInput)

        // Verify that CLI and GUI produce IDENTICAL assembler, daemon, and ledger calls
        XCTAssertEqual(spiesCLI.assembler.roomIDs, spiesGUI.assembler.roomIDs)
        XCTAssertEqual(spiesCLI.daemon.opens, spiesGUI.daemon.opens)
        XCTAssertEqual(spiesCLI.ledger.occupancies, spiesGUI.ledger.occupancies)
    }

    func testOpenRollsBackCredentialsWhenDaemonFails() async throws {
        struct FailingDaemon: DaemonSessionControlling, Sendable {
            func openSession(
                roomDir: String,
                envFile: String,
                shell: String,
                seatbeltProfile: String?
            ) throws -> String {
                throw DaemonProtocolError.requestFailed("socket failed")
            }
            func openSession(
                roomDir: String,
                envFile: String,
                shell: String,
                seatbeltProfile: String?,
                sessionRole: String?,
                columns: Int?,
                rows: Int?,
                banner: String?
            ) throws -> String {
                throw DaemonProtocolError.requestFailed("socket failed")
            }
            func closeSession(sessionID: String) throws {}
            func listSessions() throws -> [RoomListedSession] { [] }
            func ensureNetworkProxy(roomDir: String, allowedDomains: [String]) throws -> UInt16 { 0 }
        }
        final class SpyCredentialSeeder: CredentialSeeding, Sendable {
            private struct State: Sendable {
                var seeded = false
                var unseededAll = false
            }
            private let state = OSAllocatedUnfairLock(initialState: State())

            var seeded: Bool { state.withLock { $0.seeded } }
            var unseededAll: Bool { state.withLock { $0.unseededAll } }

            func seed(tool: AgentRoomTool, roomURL: URL) -> AgentCredentialInjector.SeedOutcome {
                state.withLock { $0.seeded = true }
                return .seeded
            }
            func unseed(tool: AgentRoomTool, roomURL: URL) -> Bool { true }
            func unseedAll(roomURL: URL) -> Bool {
                state.withLock { $0.unseededAll = true }
                return true
            }
        }
        let seeder = SpyCredentialSeeder()
        let spies = Spies()
        let ctx = makeContext()
        let pipeline = RoomOpenPipeline(
            ledgerLookup: ResolverLedgerLookup(resolver: DictionaryRoomActionResolver(contexts: [ctx.spec.roomID: ctx])),
            complianceChecker: AllowAll(),
            assembler: spies.assembler,
            credentialSeeder: seeder,
            daemon: FailingDaemon(),
            ledgerOccupancy: spies.ledger
        )
        do {
            _ = try await pipeline.open(RoomOpenPipelineInput(roomID: ctx.spec.roomID, environment: ctx.spec.environment))
            XCTFail("expected open to throw")
        } catch {
            XCTAssertTrue(seeder.seeded)
            XCTAssertTrue(seeder.unseededAll)
        }
    }

    func testCloseCallsDaemonThenLedger() async throws {
        let spies = Spies()
        let ctx = makeContext()
        try await spies.actions(ctx).closeRoom(id: ctx.spec.roomID)
        XCTAssertEqual(spies.daemon.closes, [ctx.sessionID])
        XCTAssertEqual(spies.ledger.closes, [
            CloseLedgerCall(
                plan: ctx.planID,
                workdir: ctx.roomURL.path,
                seatedRoomID: ctx.authority.seatedRoomID
            ),
        ])
    }

    func testCloseRoomWipesCredentialFile() async throws {
        let fm = FileManager.default
        let tempRoom = fm.temporaryDirectory.appendingPathComponent(
            "core-actions-close-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: tempRoom) }

        let dir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: tempRoom)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let credFile = dir.appendingPathComponent(".credentials.json")
        try Data(#"{"token":"secret-token"}"#.utf8).write(to: credFile)
        XCTAssertTrue(fm.fileExists(atPath: credFile.path))

        let spies = Spies()
        var ctx = makeContext()
        ctx.roomURL = tempRoom
        try await spies.actions(ctx).closeRoom(id: ctx.spec.roomID)

        XCTAssertFalse(fm.fileExists(atPath: credFile.path))
    }

    func testHandoffForwardsExactRequest() async throws {
        let spies = Spies()
        let ctx = makeContext()
        try await spies.actions(ctx).handoff(roomID: ctx.spec.roomID)
        XCTAssertEqual(spies.handoff.requests.count, 1)
        let request = try XCTUnwrap(spies.handoff.requests.first)
        XCTAssertEqual(request.roomID, ctx.handoff.roomID)
        XCTAssertEqual(request.roomURL, ctx.handoff.roomURL)
        XCTAssertEqual(request.planID, ctx.handoff.planID)
        XCTAssertEqual(request.note, ctx.handoff.note)
        XCTAssertEqual(request.sessionID, ctx.handoff.sessionID)
        XCTAssertEqual(request.authority, ctx.handoff.authority)
        XCTAssertEqual(request.tool, ctx.handoff.tool)
        XCTAssertEqual(request.wallMode, ctx.handoff.wallMode)
    }

    func testSimulateForwardsRoomHandoffAndAuthority() async throws {
        let spies = Spies()
        let ctx = makeContext()
        try await spies.actions(ctx).simulate(roomID: ctx.spec.roomID)
        XCTAssertEqual(spies.simulator.calls, [
            SimulateCall(
                room: ctx.roomURL,
                handoffID: ctx.handoffID,
                seatedRoomID: ctx.authority.seatedRoomID
            ),
        ])
    }

    func testShowHabitsListsTheRoomFolder() async throws {
        let spies = Spies()
        let ctx = makeContext()
        try await spies.actions(ctx).showHabits(roomID: ctx.spec.roomID)
        XCTAssertEqual(spies.habits.rooms, [ctx.roomURL])
    }

    private struct Spies {
        let assembler = SpyAssembler()
        let daemon = SpyDaemon()
        let ledger = OccupancyLedgerSpy()
        let handoff = SpyHandoff()
        let simulator = SpySimulator()
        let habits = SpyHabits()

        func actions(_ ctx: RoomActionContext) -> CoreRoomActions {
            CoreRoomActions(
                assembler: assembler,
                daemon: daemon,
                ledger: ledger,
                handoff: handoff,
                simulator: simulator,
                habits: habits,
                resolver: DictionaryRoomActionResolver(contexts: [ctx.spec.roomID: ctx])
            )
        }
    }

    private func makeContext() -> RoomActionContext {
        let roomURL = URL(fileURLWithPath: "/tmp/rooms/room-open-1", isDirectory: true)
        let authority = LedgerAuthority.commandRoom(
            sessionID: "auth-session",
            seatedRoomID: "room-open-1"
        )
        let spec = RoomAssemblySpec(
            roomID: "room-open-1",
            slug: "gujo-seller-operations",
            tenantSlug: "gujo",
            layoutID: "layout-1",
            blueprint: RoomBlueprintSnapshot(
                task: "판매 카탈로그를 운영한다",
                verdict: "true"
            ),
            tenantPolicy: RoomTenantPolicy(stateRoot: "/tmp/state", wikiWorld: "tenant-gujo"),
            budget: RoomBudgetSnapshot(
                window: 1_000_000,
                trigger: 0.835,
                initialInput: 100,
                reservedOutput: 0,
                usable: 834_900,
                handoffAt: 667_920
            ),
            compliance: AllowAll(),
            environment: ["SWIFT_APP_STATE_ROOT": "/tmp/state"],
            homeDirectory: "/tmp/home"
        )
        let budget = Budget.compute(
            tool: .claude,
            initialInput: 100,
            used: 10,
            elapsedMinutes: 1,
            estimatedWorkMinutes: 60
        )
        let handoff = HandoffRequest(
            roomID: spec.roomID,
            roomURL: roomURL,
            planID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            note: "남은 일을 넘긴다",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: "pred-agent",
            successorOccupant: "succ-agent",
            successorHandle: "succ-handle",
            sessionID: "pty-session",
            wallMode: "full",
            authority: authority
        )
        let expectedProfile = RoomOpenPolicy.seatbeltProfile(
            preset: spec.blueprint.preset,
            roomPath: roomURL.path,
            writePaths: spec.blueprint.walls.writePaths,
            network: spec.blueprint.walls.network,
            agentTools: spec.blueprint.agentTools,
            proxyPort: nil,
            workdir: spec.blueprint.workdir
        )
        let expectedOccupant = RoomOpenPipeline.occupant(tool: .claude)
        return RoomActionContext(
            spec: spec,
            roomURL: roomURL,
            envFile: roomURL.appendingPathComponent("env").path,
            shell: "zsh -r",
            seatbeltProfile: expectedProfile,
            sessionID: "pty-session",
            planID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            occupant: expectedOccupant,
            wallMode: "full",
            authority: authority,
            handoff: handoff,
            handoffID: "handoff-1"
        )
    }
}
