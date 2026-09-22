import Foundation
import AppKit
import Observation
import LocalizationKit
import AgentRoomTerminalCore
import TerminalEngineKit
import TerminalEngineGhostty
import RadialGraphUIKit
import TimelineGraphUIKit

struct PendingRoomAction: Equatable {
    var op: String
    var roomID: String
}

/// 실제 방 표면 상태 — 배제 도구·사유·방 세우기 시트 입력.
struct RoomSurfaceState {
    var excludedToolsByRoom: [String: [String]] = [:]
    var exclusionReasons: [String: [String: String]] = [:]
    var standUpBlueprints: [RoomBlueprintPick] = []
    var standUpTenants: [String] = []
    var realRoomCount = 0
    var wallEnforcementByRoom: [String: String] = [:]
    /// room-graph.json 좌석 사슬(roomID → 전임·현임·후임). 감시자는 파일 mtime 알림만.
    var seatChains: RoomSeatChainLoad = .notLoaded
    var seatChainWatcher: RoomGraphFileWatcher?
}

struct RoomStatusTracking {
    var lastByteReceived: [String: Date] = [:]
    var hasWaitingEvent: [String: Bool] = [:]
    var processTerminated: [String: Bool] = [:]
    var attachErrors: [String: Bool] = [:]
}

struct TerminalSessionCache {
    var engines: [String: GhosttyTerminalEngine] = [:]
    var bridges: [String: RoomTerminalBridge] = [:]
    var observers: [String: any TerminalEngineEvents] = [:]
}

struct DaemonConnectionState {
    var client: DaemonClient?
    var running = false
    var generation: UInt64 = 0
}

struct RoomFilterState {
    var filter: RoomListFilterMode = .active
    var query: String = ""
    var viewMode: MainViewMode = .canvas
    var canvasTenantFilter: String = "all"
    var canvasHideInactive: Bool = true
}

struct RoomStatusTimerState {
    var tick: UInt64 = 0
    var task: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
}

enum MainViewMode: String, CaseIterable, Equatable {
    case terminal
    case canvas
    case perspective
}

struct TuningState {
    let source: any TuningReading
    let loadError: String?
    var current: CanvasTuning = .factory
}

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = AgentRoomTerminalService()
    var tuningState: TuningState

    var tuningSource: any TuningReading { tuningState.source }
    var tuningLoadError: String? { tuningState.loadError }
    var tuning: CanvasTuning {
        get { tuningState.current }
        set { tuningState.current = newValue }
    }

    var status: String = ""
    var errorMessage: String?
    var nodes: [RoomSummary] = []
    var selectedID: String?
    var filterState = RoomFilterState()
    var usingFixture = true
    var lastAction: String = ""
    var connection = DaemonConnectionState()
    var actions: any RoomActions
    var actionResolver = DictionaryRoomActionResolver()
    var pendingAction: PendingRoomAction?
    var roomSurface = RoomSurfaceState()
    var tracking = RoomStatusTracking()
    var terminalCache = TerminalSessionCache()
    var statusTimer = RoomStatusTimerState()
    var resultBadges: [String: RoomResultBadge] = [:]

    var statusTick: UInt64 {
        get { statusTimer.tick }
        set { statusTimer.tick = newValue }
    }

    var listFilter: RoomListFilterMode {
        get { filterState.filter }
        set { filterState.filter = newValue }
    }
    var searchQuery: String {
        get { filterState.query }
        set { filterState.query = newValue }
    }
    var viewMode: MainViewMode {
        get { filterState.viewMode }
        set { filterState.viewMode = newValue }
    }
    var canvasTenantFilter: String {
        get { filterState.canvasTenantFilter }
        set { filterState.canvasTenantFilter = newValue }
    }
    var canvasHideInactive: Bool {
        get { filterState.canvasHideInactive }
        set { filterState.canvasHideInactive = newValue }
    }
    var daemonClient: DaemonClient? {
        get { connection.client }
        set { connection.client = newValue }
    }
    var daemonRunning: Bool {
        get { connection.running }
        set { connection.running = newValue }
    }
    var daemonGeneration: UInt64 {
        get { connection.generation }
        set { connection.generation = newValue }
    }
    var lastByteReceived: [String: Date] {
        get { tracking.lastByteReceived }
        set { tracking.lastByteReceived = newValue }
    }
    var hasWaitingEvent: [String: Bool] {
        get { tracking.hasWaitingEvent }
        set { tracking.hasWaitingEvent = newValue }
    }
    var processTerminated: [String: Bool] {
        get { tracking.processTerminated }
        set { tracking.processTerminated = newValue }
    }
    var attachErrors: [String: Bool] {
        get { tracking.attachErrors }
        set { tracking.attachErrors = newValue }
    }

    var filteredRooms: [RoomSummary] {
        RoomListFilter.filter(nodes: nodes, mode: listFilter, query: searchQuery)
    }

    var groupedRooms: [(tenant: String, rooms: [RoomSummary])] {
        RoomListFilter.groupByTenant(nodes: filteredRooms)
    }

    var selectedNode: RoomSummary? {
        guard let id = selectedID else { return nil }
        return nodes.first { $0.id == id }
    }

    var pendingActionTitle: String {
        switch pendingAction?.op {
        case "open": return L(.menuOpenRoom)
        case "close": return L(.menuCloseRoom)
        case "handoff": return L(.menuHandoff)
        case "simulate": return L(.menuSimulate)
        case "habits": return L(.menuHabits)
        default: return L(.menuRefresh)
        }
    }

    init() {
        let source: any TuningReading
        let err: String?
        do {
            source = try PersistentTuning(store: .default())
            err = nil
        } catch {
            source = InMemoryTuning()
            err = error.localizedDescription
        }
        let snap = source.snapshot()
        self.tuningState = TuningState(source: source, loadError: err, current: snap)
        actions = RecordingRoomActions()
        actions = RecordingRoomActions { [weak self] log in
            Task { @MainActor in
                self?.lastAction = "\(log.op):\(log.roomID)"
            }
        }
        nodes = RoomCanvasFixture.nodes()
        selectedID = nodes.first(where: { $0.kind.hostsTerminal })?.id
        startStatusTimer()
        startRefreshTimer()
        reloadSeatChains()
        startSeatChainWatch()
        Task { await self.refresh() }
    }

    func startStatusTimer() {
        guard statusTimer.task == nil else { return }
        statusTimer.task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
                guard let self else { break }
                self.statusTimer.tick &+= 1
            }
        }
    }

    func startRefreshTimer() {
        guard statusTimer.refreshTask == nil else { return }
        statusTimer.refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    break
                }
                guard let self else { break }
                await self.refresh()
            }
        }
    }

    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ value: Int) -> String {
        let raw = loc.string(key.rawValue)
        return CLILocalization.substituteSlots(into: raw, values: [value])
    }

    func selectRoom(id: String) {
        selectedID = id
    }

    func statusDot(for room: RoomSummary) -> RoomTerminalStatusDot {
        _ = statusTick
        return RoomTerminalStatusDot.judge(
            status: room.status,
            lastByteReceivedAt: lastByteReceived[room.id],
            hasWaitingEvent: hasWaitingEvent[room.id] ?? false,
            hasAttachError: attachErrors[room.id] ?? false
        )
    }

    func resultBadge(for roomID: String) -> RoomResultBadge {
        resultBadges[roomID] ?? .none
    }

    nonisolated private static func resolveWorkdir(roomID: String) -> String? {
        guard let folder = try? RoomFolderLocator.find(roomID: roomID) else { return nil }
        let specURL = folder.appendingPathComponent("spec.json", isDirectory: false)
        guard let data = try? Data(contentsOf: specURL) else { return nil }
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["workdir"] as? String
        } catch {
            return nil
        }
    }

    nonisolated private static func loadBadges(for snapshotNodes: [RoomSummary]) -> [String: RoomResultBadge] {
        var map: [String: RoomResultBadge] = [:]
        for node in snapshotNodes {
            let fields = RoomResultResolver.resolve(
                roomID: node.id,
                roomDirectoryResolver: { id in try? RoomFolderLocator.find(roomID: id) },
                workdirResolver: Self.resolveWorkdir,
                fileReader: { try? Data(contentsOf: $0) }
            )
            if fields.statusBadge != .none {
                map[node.id] = fields.statusBadge
            }
        }
        return map
    }

    func loadResultBadgeIfNeeded(for roomID: String) {
        guard resultBadges[roomID] == nil else { return }
        Task.detached(priority: .utility) {
            let fields = RoomResultResolver.resolve(
                roomID: roomID,
                roomDirectoryResolver: { id in try? RoomFolderLocator.find(roomID: id) },
                workdirResolver: Self.resolveWorkdir,
                fileReader: { try? Data(contentsOf: $0) }
            )
            let badge = fields.statusBadge
            await MainActor.run { [weak self] in
                self?.resultBadges[roomID] = badge
            }
        }
    }

    private func applySnapshotData(_ snapshot: RoomTreeSource.Snapshot, sessions: [String: String]) async {
        guard !usingFixture else {
            actionResolver = DictionaryRoomActionResolver()
            roomSurface.excludedToolsByRoom = [:]
            roomSurface.exclusionReasons = [:]
            resultBadges = [:]
            return
        }
        nodes = snapshot.nodes
        fillActionResolver(sessions: sessions)
        let excluded = roomSurface.excludedToolsByRoom
        roomSurface.exclusionReasons = await Task.detached(priority: .utility) {
            ExclusionReasonLoader.reasons(excludedToolsByRoom: excluded)
        }.value
        let snapshotNodes = snapshot.nodes
        self.resultBadges = await Task.detached(priority: .utility) {
            Self.loadBadges(for: snapshotNodes)
        }.value
    }

    func refresh() async {
        do {
            try service.ensureDurableStore()
            status = try await service.status()
            errorMessage = nil
            probeDaemon()
            let sessions = liveSessionsByRoomDir()
            let snapshot = try RoomTreeSource.snapshot(
                sessionsByRoomDir: sessions,
                commandRoomTitle: L(.canvasCommandRoom)
            )
            usingFixture = snapshot.nodes.isEmpty
            roomSurface.realRoomCount = snapshot.roomCount
            await applySnapshotData(snapshot, sessions: sessions)
            // 목록에서 사라진 방들의 터미널 세션 정리
            let currentRoomIDs = Set(nodes.map(\.id))
            let cachedIDs = Array(terminalCache.engines.keys)
            for cachedID in cachedIDs where !currentRoomIDs.contains(cachedID) {
                cleanupTerminalSession(roomID: cachedID)
            }

            if let currentSelected = selectedID, nodes.contains(where: { $0.id == currentSelected }) {
                // 선택 유지
            } else {
                selectedID = filteredRooms.first?.id ?? nodes.first(where: { $0.kind.hostsTerminal })?.id ?? nodes.first?.id
            }
            bindActions()
            publishMirror()
        } catch {
            let message = String(describing: error)
            errorMessage = message
            publishMirror()
        }
    }

    func bindActions() {
        if usingFixture {
            actions = RecordingRoomActions { [weak self] log in
                Task { @MainActor in
                    self?.lastAction = "\(log.op):\(log.roomID)"
                    self?.publishMirror()
                }
            }
            return
        }
        let client = daemonClient ?? DaemonClient(socketURL: AppPaths.daemonSocketURL())
        daemonClient = client
        actions = CoreRoomActions.live(client: client, resolver: actionResolver)
    }

    func fillActionResolver(sessions: [String: String]) {
        let environment = ProcessInfo.processInfo.environment
        let folders = (try? RoomFolderLocator.allRooms(tenant: nil, environment: environment)) ?? []
        var contexts: [String: RoomActionContext] = [:]
        var excluded: [String: [String]] = [:]
        for folder in folders {
            let document: RoomDocument
            do {
                document = try RoomDocument.load(from: folder)
            } catch {
                continue
            }
            let session = sessions[SessionAuthorizer.standardized(folder.path)]
            contexts[document.id] = RoomActionBinding.context(
                folder: folder,
                document: document,
                sessionID: session,
                environment: environment
            )
            excluded[document.id] = document.excludedTools
        }
        actionResolver = DictionaryRoomActionResolver(contexts: contexts)
        roomSurface.excludedToolsByRoom = excluded
    }

    func requestRoomAction(op: String, roomID: String) {
        if usingFixture || op == "habits" {
            Task { await runRoomAction(op: op, roomID: roomID) }
            return
        }
        pendingAction = PendingRoomAction(op: op, roomID: roomID)
    }

    func confirmPendingAction() async {
        guard let pending = pendingAction else { return }
        pendingAction = nil
        await runRoomAction(op: pending.op, roomID: pending.roomID)
    }

    func runRoomAction(op: String, roomID: String) async {
        do {
            try await dispatchAction(op: op, roomID: roomID)
            lastAction = "\(op):\(roomID)"
            probeDaemon()
            publishMirror()
        } catch {
            errorMessage = String(describing: error)
            publishMirror()
        }
    }

    func standUp(slug: String, tenant: String) async {
        let environment = ProcessInfo.processInfo.environment
        guard let pick = roomSurface.standUpBlueprints.first(where: { $0.slug == slug }) else {
            errorMessage = RoomStandUpError.blueprintMissing(slug).localizedDescription
            publishMirror()
            return
        }
        do {
            errorMessage = nil
            let plan = try RoomStandUpClient.instantiate(slug: slug, tenant: tenant)
            var contexts = actionResolver.contexts
            contexts[plan.roomID] = RoomActionBinding.context(
                plan: plan,
                pick: pick,
                environment: environment
            )
            actionResolver = DictionaryRoomActionResolver(contexts: contexts)
            usingFixture = false
            bindActions()
            try await actions.openRoom(id: plan.roomID)
            lastAction = "open:\(plan.roomID)"
            await refresh()
        } catch {
            errorMessage = String(describing: error)
            publishMirror()
        }
    }
}

/// 좌석 사슬 파일 읽기 결과. 실패도 상태다 — 화면이 이유를 보인다.
enum RoomSeatChainLoad: Equatable {
    case notLoaded
    case loaded(RoomGraphSeatChainFeed)
    case failed(String)
}
