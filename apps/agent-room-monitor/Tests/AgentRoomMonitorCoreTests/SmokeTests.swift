import XCTest
import AppScaffoldKit
import CommandKit
@testable import AgentRoomMonitorCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "agent-room-monitor"))
    }
}

final class SnapshotBuilderTests: XCTestCase {
    struct MockFetch: OwnerFetching {
        var placements: [PlacementDTO] = []
        var blueprints: [BlueprintDTO] = []
        var seats: [SeatDTO] = []
        var deck: AgentDeckStateDTO? = nil
        var ship = ShipBridge()
        var vault = VaultBridge(cards: 0, grants: 0, infisical: 0)
        var host = HostPulse()
        var permission = PermissionBridge(summary: "ok")
        var archive = 0
        var skills: [String] = []
        var usage: [String: SkillUsage] = [:]
        var usageNote: String? = nil
        var tenant = TenantBridge()
        var sessions: [SessionCardDTO] = []
        var hooks = HooksBridge()
        var reach = ReachBridge()

        func placements() async -> BridgeResult<[PlacementDTO]> { BridgeResult(value: placements) }
        func blueprints() async -> BridgeResult<[BlueprintDTO]> { BridgeResult(value: blueprints) }
        func seats() async -> BridgeResult<[SeatDTO]> { BridgeResult(value: seats) }
        func deck() async -> BridgeResult<AgentDeckStateDTO?> { BridgeResult(value: deck) }
        func shipJobs() async -> BridgeResult<ShipBridge> { BridgeResult(value: ship) }
        func vault() async -> BridgeResult<VaultBridge> { BridgeResult(value: vault) }
        func hostPulse() async -> BridgeResult<HostPulse> { BridgeResult(value: host) }
        func permission() async -> BridgeResult<PermissionBridge> { BridgeResult(value: permission) }
        func sessionArchive() async -> BridgeResult<Int> { BridgeResult(value: archive) }
        func installedSkills() async -> BridgeResult<[String]> { BridgeResult(value: skills) }
        func skillUsage() async -> BridgeResult<[String: SkillUsage]> { BridgeResult(value: usage, note: usageNote) }
        func tenants() async -> BridgeResult<TenantBridge> { BridgeResult(value: tenant) }
        func sessions() async -> BridgeResult<[SessionCardDTO]> { BridgeResult(value: sessions) }
        func hooks() async -> BridgeResult<HooksBridge> { BridgeResult(value: hooks) }
        func reach() async -> BridgeResult<ReachBridge> { BridgeResult(value: reach) }
    }

    func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            XCTFail("임시 디렉터리 생성 실패: \(error)")
        }
        return dir
    }

    func testBuildWithFixtures() async throws {
        var fetch = MockFetch()
        fetch.placements = [
            PlacementDTO(
                id: "PLACEMENT-1", title: "테스트 배치도", state: "active",
                rooms: [PlacementRoomDTO(id: "ROOM-1", blueprintSlug: "command-room", state: "executing", blockedCount: 0, humanGate: false)]
            )
        ]
        fetch.blueprints = [BlueprintDTO(slug: "command-room", toolbelt: ["skill-a"])]
        fetch.seats = [SeatDTO(handle: "claude", occupant: "claude", kind: "worker", model: "sonnet")]
        fetch.deck = AgentDeckStateDTO(agents: 3, agentsWorking: 1, archivedSessions: 10)
        fetch.ship = ShipBridge(
            jobs: [ShipJobDTO(id: "J1", dirName: "demo-swift", status: "queued", enqueuedAt: "2026-08-20T00:00:00Z")],
            load1: 1.23, ncpu: 8
        )
        fetch.skills = ["skill-a", "skill-b"]
        fetch.usage = ["skill-a": SkillUsage(callCount: 2, lastCalledAt: 1_700_000_000)]
        fetch.host = HostPulse(load1: 1.23)
        fetch.vault = VaultBridge(cards: 1, grants: 1, infisical: 1, tenant: "tenant:test")

        let snapshot = await SnapshotBuilder(fetcher: fetch).build()

        XCTAssertTrue(snapshot.root.health.notes.isEmpty, "실데이터가 다 있으면 note 없어야 함: \(snapshot.root.health.notes)")
        let workRooms = snapshot.root.children.first(where: { $0.id == "work-rooms" })
        XCTAssertEqual(workRooms?.children.count, 1)
        XCTAssertEqual(workRooms?.children.first?.children.first?.state, .exec)

        let skillsNode = snapshot.root.children.first(where: { $0.id == "skill-warehouse" })
        XCTAssertEqual(skillsNode?.children.count, 3)
        let unreferenced = skillsNode?.children.first(where: { $0.id == "skill-unreferenced" })
        XCTAssertEqual(unreferenced?.children.count, 1)

        let seatsNode = snapshot.root.children.first(where: { $0.id == "seats" })
        XCTAssertEqual(seatsNode?.children.first?.agent?.actor, "claude")

        XCTAssertEqual(snapshot.telemetry.ncpu, 8)
        XCTAssertEqual(snapshot.telemetry.load1, 1.23)

        XCTAssertNotNil(snapshot.root.children.first(where: { $0.id == "lobby" }))
        XCTAssertNotNil(snapshot.root.children.first(where: { $0.id == "archive" }))
        XCTAssertNotNil(snapshot.root.children.first(where: { $0.id == "host-facilities" }))
    }

    func testSnapshotDiffDetectsAddedAndStateChange() {
        let old = TwinNode(id: "a", name: "A", kind: .room, state: .exec, children: [
            TwinNode(id: "r1", name: "one", kind: .room, state: .exec)
        ])
        let new = TwinNode(id: "a", name: "A", kind: .room, state: .exec, children: [
            TwinNode(id: "r1", name: "one", kind: .room, state: .block),
            TwinNode(id: "r2", name: "two", kind: .room, state: .queue)
        ])
        let diff = SnapshotDiffing.diff(old: old, new: new)
        XCTAssertEqual(diff.added, ["r2"])
        XCTAssertEqual(diff.changed, ["a", "r1"])
        XCTAssertTrue(diff.removed.isEmpty)
    }

    func testMutationServiceCallsOwnerCLI() async {
        actor Box {
            var path = ""
            var args: [String] = []
            func record(_ launchPath: String, _ arguments: [String]) {
                path = launchPath
                args = arguments
            }
        }
        struct Runner: CommandRunning {
            let box: Box
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                await box.record(launchPath, arguments)
                return CommandResult(stdout: "ok\n", stderr: "", exitCode: 0)
            }
        }
        let box = Box()
        let svc = RoomMutationService(runner: Runner(box: box))
        let result = await svc.perform(.occupy(planID: "P1", roomID: "R1", occupant: "agent:grok@macbook"))
        XCTAssertTrue(result.ok)
        var args = await box.args
        XCTAssertEqual(args, ["placement", "occupy", "P1", "R1", "--occupant", "agent:grok@macbook"])
        let spawned = await svc.perform(.spawnRoom(
            task: "도메인 일", verify: "true", handle: "부엉이",
            occupant: "agent:grok@macbook", workdir: "/tmp/x", tenant: "tenant:personal",
            tools: ["agent-wiki"], writes: []
        ))
        XCTAssertTrue(spawned.ok)
        args = await box.args
        XCTAssertEqual(args.first, "placement")
        XCTAssertEqual(args.dropFirst().first, "spawn-room")
        XCTAssertTrue(args.contains("tenant:personal"))
        XCTAssertTrue(args.contains("agent-room-monitor"))
        let attached = await svc.perform(.attachSkill(slug: "cmd-room", tool: "agent-wiki"))
        XCTAssertTrue(attached.ok)
        args = await box.args
        XCTAssertEqual(args, ["room", "toolbelt-add", "cmd-room", "--tool", "agent-wiki"])

        let blocked = await svc.perform(.spawnRoom(
            task: "일", verify: "true", handle: "tenant:personal",
            occupant: "agent:grok@macbook", workdir: "/tmp/x", tenant: "tenant:personal",
            tools: [], writes: []
        ))
        XCTAssertFalse(blocked.ok)
        XCTAssertEqual(blocked.exitCode, 64)
        XCTAssertTrue(blocked.stderr.contains("이름 게이트"))
    }

    func testMutationServiceTickTimeoutAndWorkdir() async {
        actor Box {
            var path = ""
            var args: [String] = []
            var timeout: TimeInterval?
            func record(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) {
                self.path = launchPath
                self.args = arguments
                self.timeout = timeout
            }
        }
        struct Runner: CommandRunning {
            let box: Box
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                await box.record(launchPath, arguments, timeout: timeout)
                return CommandResult(stdout: "ok\n", stderr: "", exitCode: 0)
            }
        }
        let box = Box()
        let svc = RoomMutationService(runner: Runner(box: box))
        let ticked = await svc.perform(.tick(planID: "PLAN-123", workdir: "/tmp/my-workdir"))
        XCTAssertTrue(ticked.ok)
        let args = await box.args
        XCTAssertEqual(args, ["placement", "tick", "PLAN-123", "--workdir", "/tmp/my-workdir"])
        let timeout = await box.timeout
        XCTAssertEqual(timeout, 180.0)
    }

    func testRejectPlacementClosesPlanViaPlacementReject() async {
        actor Box {
            var path = ""
            var args: [String] = []
            func record(_ launchPath: String, _ arguments: [String]) {
                path = launchPath
                args = arguments
            }
        }
        struct Runner: CommandRunning {
            let box: Box
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                await box.record(launchPath, arguments)
                return CommandResult(stdout: "ok\n", stderr: "", exitCode: 0)
            }
        }
        let box = Box()
        let svc = RoomMutationService(runner: Runner(box: box))
        let result = await svc.perform(.rejectPlacement(planID: "P9", by: "agent-room-monitor"))
        XCTAssertTrue(result.ok)
        let args = await box.args
        // 반려는 심사 기록(review --fail)이 아니라 반려 종결(reject)이어야
        // executing 배치도가 실제로 닫힌다.
        XCTAssertEqual(args, [
            "placement", "reject", "P9",
            "--by", "agent-room-monitor",
            "--reason", "room-monitor demolish",
            "--json"
        ])
        XCTAssertFalse(args.contains("--fail"))
    }

    func testOccupancyAXSummarizeWalksRoles() {
        let json = #"{"result":{"role":"AXWindow","title":"Board","children":[{"role":"AXButton","title":"Enter"}]}}"#
        let text = OccupancyAX.summarize(json)
        XCTAssertTrue(text.contains("Board"))
        XCTAssertTrue(text.contains("Enter"))
    }

    func testBuildSurvivesMissingSources() async throws {
        struct EmptyFail: OwnerFetching {
            func placements() async -> BridgeResult<[PlacementDTO]> { BridgeResult(value: [], note: "없음") }
            func blueprints() async -> BridgeResult<[BlueprintDTO]> { BridgeResult(value: []) }
            func seats() async -> BridgeResult<[SeatDTO]> { BridgeResult(value: []) }
            func deck() async -> BridgeResult<AgentDeckStateDTO?> { BridgeResult(value: nil) }
            func shipJobs() async -> BridgeResult<ShipBridge> { BridgeResult(value: ShipBridge()) }
            func vault() async -> BridgeResult<VaultBridge> { BridgeResult(value: VaultBridge(cards: 0, grants: 0, infisical: 0)) }
            func hostPulse() async -> BridgeResult<HostPulse> { BridgeResult(value: HostPulse()) }
            func permission() async -> BridgeResult<PermissionBridge> { BridgeResult(value: PermissionBridge(summary: "없음")) }
            func sessionArchive() async -> BridgeResult<Int> { BridgeResult(value: 0) }
            func installedSkills() async -> BridgeResult<[String]> { BridgeResult(value: []) }
            func skillUsage() async -> BridgeResult<[String: SkillUsage]> { BridgeResult(value: [:], note: "ledger 실패") }
            func tenants() async -> BridgeResult<TenantBridge> { BridgeResult(value: TenantBridge()) }
            func sessions() async -> BridgeResult<[SessionCardDTO]> { BridgeResult(value: []) }
            func hooks() async -> BridgeResult<HooksBridge> { BridgeResult(value: HooksBridge()) }
            func reach() async -> BridgeResult<ReachBridge> { BridgeResult(value: ReachBridge()) }
        }
        let snapshot = await SnapshotBuilder(fetcher: EmptyFail()).build()
        XCTAssertFalse(snapshot.root.health.notes.isEmpty)
        XCTAssertEqual(snapshot.root.children.count, 8)
    }

    func testTraceStoreRecordAndLoad() throws {
        let dir = makeTempDir().appendingPathComponent("trace", isDirectory: true)
        let store = TraceStore(root: dir)
        let event = TraceEvent(t: 100, lane: 1, label: "tool call", state: .exec)
        try store.record(event, sessionID: "sess-1")
        let loaded = store.load(sessionID: "sess-1")
        XCTAssertEqual(loaded, [event])
    }

    func testUsageFailureDoesNotMarkEverySkillUncalled() async throws {
        var fetch = MockFetch()
        fetch.skills = ["skill-a"]
        fetch.usageNote = "timeout"
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        let uncalled = snapshot.root.children
            .first(where: { $0.id == "skill-warehouse" })?
            .children.first(where: { $0.id == "skill-uncalled" })
        XCTAssertEqual(uncalled?.children.count, 0)
        XCTAssertEqual(uncalled?.state, .gate)
        XCTAssertFalse(snapshot.trace.contains(where: { $0.lane == 4 }))
    }

    func testViewpointTreatsCurrentWorkdirAsFirstPerson() {
        let here = "/Users/jeonghan/Documents/WORK/WORKSPACE/apps/swift-app-mono/.worktrees/main"
        XCTAssertEqual(SnapshotBuilder.viewpoint(workdir: here, here: here), "first")
        XCTAssertEqual(SnapshotBuilder.viewpoint(workdir: "/Volumes/film", here: here), "third")
        XCTAssertEqual(SnapshotBuilder.viewpoint(workdir: nil, here: here), "third")
    }

    func testTenantBuildingsKeepSilneobalOutOfPersonal() async {
        var fetch = MockFetch()
        fetch.tenant = TenantBridge(
            currentID: "tenant:personal",
            listed: [TenantRef(id: "tenant:personal", displayName: "개인", current: true)]
        )
        fetch.placements = [
            PlacementDTO(
                id: "P-PERSONAL", title: "개인 방", state: "active",
                rooms: [PlacementRoomDTO(id: "R1", blueprintSlug: "cmd", state: "executing")],
                tenantID: "tenant:personal"
            )
        ]
        fetch.seats = [
            SeatDTO(handle: "film", occupant: "grok", kind: "worker",
                    workdir: "/Volumes/film", keys: SeatKeysDTO(tenant: "tenant:silneobal"))
        ]
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        XCTAssertTrue(snapshot.tenants.contains(where: { $0.id == "tenant:silneobal" }))
        let personal = snapshot.root.children.first(where: { $0.id == "tenant-tenant:personal" })
        let film = snapshot.root.children.first(where: { $0.id == "tenant-tenant:silneobal" })
        XCTAssertNotNil(personal)
        XCTAssertNotNil(film)
        let personalSeats = personal?.children.first(where: { $0.id.hasPrefix("seats-") })
        XCTAssertFalse(personalSeats?.children.contains(where: { $0.id == "seat-film" }) ?? true)
        XCTAssertTrue(film?.children.contains(where: { zone in
            zone.children.contains(where: { $0.id == "seat-film" })
        }) ?? false)
        let commons = snapshot.root.children.first(where: { $0.id == "fleet-commons" })
        XCTAssertEqual(commons?.viewpoint, "third")
        let homeIDs = personal?.children.map(\.id) ?? []
        XCTAssertTrue(homeIDs.contains(where: { $0.hasPrefix("work-rooms") }))
        XCTAssertTrue(homeIDs.contains(where: { $0.hasPrefix("skill-warehouse") }))
        XCTAssertFalse(homeIDs.contains(where: { $0.hasPrefix("skill-") && !$0.hasPrefix("skill-warehouse") }))
        XCTAssertLessThanOrEqual(homeIDs.count, 25)
        let skillLeaves = personal?.children.flatMap(\.children).filter { $0.kind == .skill } ?? []
        XCTAssertTrue(skillLeaves.isEmpty, "홈 선반에 스킬 빈을 펼치면 안 된다")
    }

    func testSessionMatchingSetsPlacementAgentWithoutInventing() async {
        var fetch = MockFetch()
        fetch.tenant = TenantBridge(
            currentID: "tenant:personal",
            listed: [TenantRef(id: "tenant:personal", displayName: "개인", current: true)]
        )
        fetch.placements = [
            PlacementDTO(
                id: "P-MATCH", title: "매칭 방", state: "active",
                rooms: [PlacementRoomDTO(id: "R1", blueprintSlug: "cmd", state: "executing")],
                tenantID: "tenant:personal",
                workdir: "/tmp/room-os"
            )
        ]
        fetch.sessions = [
            SessionCardDTO(sessionId: "live-1", tool: "grok", cwd: "/tmp/room-os", displayTitle: "실측")
        ]
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        let personal = snapshot.root.children.first(where: { $0.id == "tenant-tenant:personal" })
        let work = personal?.children.first(where: { $0.id.hasPrefix("work-rooms") })
        let room = work?.children.first(where: { $0.id == "P-MATCH" })
        XCTAssertEqual(room?.agent?.sessionID, "live-1")
        XCTAssertEqual(room?.lease?.detail, "/tmp/room-os")

        fetch.sessions = []
        let empty = await SnapshotBuilder(fetcher: fetch).build()
        let emptyPersonal = empty.root.children.first(where: { $0.id == "tenant-tenant:personal" })
        let emptyRoom = emptyPersonal?.children
            .first(where: { $0.id.hasPrefix("work-rooms") })?
            .children.first(where: { $0.id == "P-MATCH" })
        XCTAssertNil(emptyRoom?.agent, "세션이 없으면 pawn을 지어내지 않는다")

        fetch.sessions = []
        fetch.seats = [
            SeatDTO(
                handle: "desk", occupant: "agent:grok@macbook", kind: "worker",
                workdir: "/tmp/room-os", keys: SeatKeysDTO(tenant: "tenant:personal"))
        ]
        let fromSeat = await SnapshotBuilder(fetcher: fetch).build()
        let seated = fromSeat.root.children
            .first(where: { $0.id == "tenant-tenant:personal" })?
            .children.first(where: { $0.id.hasPrefix("work-rooms") })?
            .children.first(where: { $0.id == "P-MATCH" })
        XCTAssertEqual(seated?.agent?.actor, "agent:grok@macbook")
    }

    func testIsolationRoomShowsOccupantAndWalls() async {
        var fetch = MockFetch()
        fetch.tenant = TenantBridge(
            currentID: "tenant:personal",
            listed: [TenantRef(id: "tenant:personal", displayName: "개인", current: true)]
        )
        fetch.blueprints = [
            BlueprintDTO(
                slug: "command-room",
                title: "지휘실",
                toolbelt: ["agent-work-todo"],
                walls: BlueprintWallsDTO(network: false, writePaths: ["apps/agent-work-todo/**"])
            )
        ]
        fetch.placements = [
            PlacementDTO(
                id: "P-CMD", title: "상주 지휘", state: "executing",
                rooms: [
                    PlacementRoomDTO(
                        id: "R-CMD", blueprintSlug: "command-room", state: "occupied",
                        occupant: "agent:codex@macbook")
                ],
                tenantID: "tenant:personal",
                workdir: "/Users/jeonghan"
            )
        ]
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        let personal = snapshot.root.children.first(where: { $0.id == "tenant-tenant:personal" })
        let work = personal?.children.first(where: { $0.id.hasPrefix("work-rooms") })
        let room = work?.children.first(where: { $0.id == "P-CMD" })?.children.first(where: { $0.id == "R-CMD" })
        XCTAssertEqual(room?.name, "지휘실")
        XCTAssertEqual(room?.agent?.actor, "agent:codex@macbook")
        XCTAssertEqual(room?.tenantID, "tenant:personal")
        XCTAssertEqual(room?.lease?.detail, "/Users/jeonghan")
        XCTAssertEqual(room?.skills.contains("agent-work-todo"), true)
        XCTAssertEqual(
            room?.attachments.contains(where: { $0.kind == "write" && $0.name == "apps/agent-work-todo/**" }),
            true)
        XCTAssertEqual(room?.attachments.first(where: { $0.kind == "net" })?.value, "0")
        XCTAssertEqual(room?.state, .exec)
        XCTAssertFalse(IsolationRisk.writesAreHomeWide(["apps/agent-work-todo/**"], home: "/Users/jeonghan"))
        XCTAssertTrue(IsolationRisk.isHomeWideWrite("/Users/jeonghan", home: "/Users/jeonghan"))
        XCTAssertTrue(IsolationRisk.isHomeWideWrite("/Users/jeonghan/**", home: "/Users/jeonghan"))
        XCTAssertTrue(IsolationRisk.isHomeWideWrite("~"))
        XCTAssertTrue(IsolationRisk.isHomeWideWrite(NSHomeDirectory() + "/**"))
        XCTAssertFalse(IsolationRisk.isHomeWideWrite("/Users/jeonghan/Documents/WORK", home: "/Users/jeonghan"))
        XCTAssertTrue(IsolationRisk.manyTools(5))
        XCTAssertFalse(IsolationRisk.manyTools(4))
        XCTAssertEqual(
            HostIdentity.occupantLabel(forgeActor: "agent:codex@studio", user: "demo", host: "box.local"),
            "agent:codex@studio")
        XCTAssertEqual(
            HostIdentity.occupantLabel(forgeActor: "  ", user: "pat", host: "studio.local"),
            "agent:pat@studio")
        XCTAssertFalse(HostIdentity.occupantLabel(user: "pat", host: "studio.local").contains("grok"))
    }

    func testSessionCardsArePagedAndNotInvented() async {
        var fetch = MockFetch()
        fetch.sessions = (0..<25).map { i in
            SessionCardDTO(sessionId: "s\(i)", tool: "grok", cwd: "/tmp", displayTitle: "일 \(i)")
        }
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        let sessions = snapshot.root.children.first(where: { $0.id == "sessions" })
        XCTAssertEqual(sessions?.children.count, 20)
        XCTAssertTrue(sessions?.health.notes.contains(where: { $0.contains("20장") }) ?? false)

        fetch.sessions = []
        let empty = await SnapshotBuilder(fetcher: fetch).build()
        let emptyNode = empty.root.children.first(where: { $0.id == "sessions" })
        XCTAssertEqual(emptyNode?.children.count, 0)
        XCTAssertTrue(emptyNode?.health.notes.contains(where: { $0.contains("지어내지") }) ?? false)

        fetch.sessions = [
            SessionCardDTO(
                sessionId: "tok", tool: "grok", cwd: "/tmp", displayTitle: "토큰 있는 세션",
                inputTokens: 12_000, contextWindow: 200_000)
        ]
        let withTokens = await SnapshotBuilder(fetcher: fetch).build()
        let card = withTokens.root.children.first(where: { $0.id == "sessions" })?.children.first
        XCTAssertEqual(card?.tokens, 12_000)
        XCTAssertEqual(card?.maxTokens, 200_000)
    }

    func testHooksLayersAppearWithoutInventingDatadog() async {
        var fetch = MockFetch()
        fetch.hooks = HooksBridge(
            ok: true, label: "OK",
            layers: [HookLayerDTO(client: "grok", layer: "user", hookCount: 3, isUserImmutable: true)],
            liveGrok: 2
        )
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        let facilities = snapshot.root.children.first(where: { $0.id == "host-facilities" })
            ?? snapshot.root.children.first(where: { $0.id == "fleet-commons" })?
            .children.first(where: { $0.id == "host-facilities" })
        let hooks = facilities?.children.first(where: { $0.id == "facility-hooks" })
        XCTAssertEqual(hooks?.children.count, 1)
        XCTAssertEqual(hooks?.children.first?.name, "grok/user")
        XCTAssertFalse((hooks?.health.notes ?? []).contains(where: { $0.lowercased().contains("datadog") }))
    }

    func testReachScanSetsInternalNetWithoutInventingExternal() async {
        var fetch = MockFetch()
        fetch.reach = ReachBridge(hasScan: true, reached: 10, unreached: 0, averageScore: 1)
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        XCTAssertEqual(snapshot.telemetry.intNetOK, true)
        XCTAssertNil(snapshot.telemetry.extNetOK)
    }

    func testTranscriptPathOnlyWhenFileExists() {
        XCTAssertNil(SnapshotBuilder.existingTranscriptPath(jsonPath: "/no/such/path", tool: "grok", sessionId: "missing"))
    }

    func testCLIJSONUnwrapsWorkTodoPayload() throws {
        let raw = #"{"command":"placement-list","ok":true,"payload":[{"id":"P1","title":"t","state":"executing"}],"schema":"v2"}"#
        let data = CLIJSON.payload(Data(raw.utf8))
        let list = try JSONDecoder().decode([PlacementDTO].self, from: data)
        XCTAssertEqual(list.first?.id, "P1")
    }

    func testPlacementWithWaitingStateButOccupiedRoomPromotesToActive() async throws {
        var fetch = MockFetch()
        fetch.placements = [
            PlacementDTO(
                id: "P-WAITING",
                title: "대기 배치도",
                state: "waiting",
                rooms: [
                    PlacementRoomDTO(id: "R-1", blueprintSlug: "worker", state: "occupied", blockedCount: 0, humanGate: false)
                ]
            )
        ]
        let snapshot = await SnapshotBuilder(fetcher: fetch).build()
        let workRooms = snapshot.root.children.first(where: { $0.id == "work-rooms" })
        XCTAssertEqual(workRooms?.children.count, 1)
        XCTAssertEqual(workRooms?.children.first?.children.first?.state, .exec)
    }
}
