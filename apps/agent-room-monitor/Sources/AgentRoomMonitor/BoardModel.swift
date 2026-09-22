import AgentRoomMonitorCore
import Foundation
import Observation

/// 보드 상태 — 모드·시점·선택·실데이터 스냅샷 로딩.
/// 하드코딩 월드 금지: 모든 데이터는 SnapshotBuilder(Core) → SnapshotAdapter 를 거친 실측이다.
@MainActor @Observable
final class BoardModel {
    enum Mode: CaseIterable {
        case now, trace, diff

        var l10nKey: L10nKey {
            switch self {
            case .now: return .modeNow
            case .trace: return .modeTrace
            case .diff: return .modeDiff
            }
        }
    }

    var world = SnapshotAdapter.emptyWorld()
    var mode: Mode = .now
    var t: Double = 10
    var selected: VNode?
    var selectedSpan: VTraceEvent?
    /// VNode(class) 내부 변경 알림용 — 데모 방 증감 시 뷰 트리 재계산.
    var tick = 0
    var refreshing = false
    var lastRefresh: Date?
    var lastOperate: String?
    var lastOperateOK: Bool = true
    var axText: String?
    var axApp: String?
    var compareDiff: SnapshotDiff?
    var spanExcerpts: [TranscriptLookup.Excerpt] = []
    /// 보드 확대율 (트랙패드 매그니파이 · 독 ±버튼).
    var zoom: CGFloat = 1
    /// 사무실 카메라 기울기. 0 = 완전 탑뷰, 0.95 = 최대 등각.
    var tilt: CGFloat = 0
    /// 사무실 카메라 요(도). 0 = 정면, Q/E 또는 ⌥드래그로 돈다.
    var yaw: CGFloat = 0
    /// 릴레이(체인) 뷰 — 이 노드의 하위가 1→2→3 순서로 옆으로 붙는다. nil = 전체 보드.
    var chainFocus: VNode?

    // VIEW-SPEC-RESTORE-MARKER — 동시 세션이 이 블록을 덮어쓰면 grep 으로 유실을 바로 안다.
    /// 디스크 뷰 정의. `~/.agent-room-monitor/views/*.json` (비면 시드 5종).
    var viewSpecs: [ViewSpec] = []
    /// 런치 인자 `-viewSpec born-48h` 가 UserDefaults 로 들어온다.
    var currentSpecID: String = UserDefaults.standard.string(forKey: BoardModel.specDefaultsKey) ?? "zone-map" {
        didSet { UserDefaults.standard.set(currentSpecID, forKey: BoardModel.specDefaultsKey) }
    }
    /// 방 속 방 드릴인 경로 (루트 쪽부터). 비면 스펙 뿌리.
    var roomPath: [VNode] = []
    /// 테넌트 필터. nil 은 아직 스냅샷 전. 기본은 isolation-manager context current.
    var selectedTenantID: String?
    enum Viewpoint: String, CaseIterable {
        case first, third
        var l10nKey: L10nKey {
            switch self {
            case .first: return .viewpointFirst
            case .third: return .viewpointThird
            }
        }
    }
    var viewpoint: Viewpoint = .first

    struct TenantBuildingSummary: Identifiable, Sendable {
        var id: String
        var displayName: String
        var isAll: Bool
        var totalRooms: Int
        var activeOccupants: Int
        var riskRooms: Int
        var isCurrent: Bool
    }

    var buildingSummaries: [TenantBuildingSummary] {
        _ = tick
        var summaries: [TenantBuildingSummary] = []
        var allRooms: [VNode] = []
        var seen = Set<String>()
        func walk(_ node: VNode) {
            switch node.kindRaw {
            case "room":
                if node.state != .done, seen.insert(node.id).inserted {
                    allRooms.append(node)
                }
            default:
                for child in node.children { walk(child) }
            }
        }
        walk(world.host)

        let allRisks = allRooms.filter { node in
            let writes = node.attachments.filter { $0.kind == "write" }.map(\.name)
            return IsolationRisk.writesAreHomeWide(writes)
        }.count
        let allActive = allRooms.filter { $0.agentKey != nil }.count

        summaries.append(TenantBuildingSummary(
            id: "__all__",
            displayName: "All Buildings",
            isAll: true,
            totalRooms: allRooms.count,
            activeOccupants: allActive,
            riskRooms: allRisks,
            isCurrent: selectedTenantID == nil
        ))

        for tenant in world.tenants {
            let tenantRooms = allRooms.filter { $0.tenantID == tenant.id }
            let risks = tenantRooms.filter { node in
                let writes = node.attachments.filter { $0.kind == "write" }.map(\.name)
                return IsolationRisk.writesAreHomeWide(writes)
            }.count
            let active = tenantRooms.filter { $0.agentKey != nil }.count
            summaries.append(TenantBuildingSummary(
                id: tenant.id,
                displayName: tenant.displayName,
                isAll: false,
                totalRooms: tenantRooms.count,
                activeOccupants: active,
                riskRooms: risks,
                isCurrent: tenant.current
            ))
        }
        return summaries
    }

    private static let specDefaultsKey = "viewSpec"

    var spec: ViewSpec? {
        viewSpecs.first(where: { $0.id == currentSpecID }) ?? viewSpecs.first
    }

    /// 실 꿰매기 렌즈 — 무엇으로 꽃들을 묶는가. 현재 뷰 정의의 groupBy 에서 파생.
    enum GroupLens: String, CaseIterable {
        case zone       // 소속 구역 (기본)
        case harness    // 하네스: claude / grok / codex …
        case runtime    // 실행 환경: orca / worktree / 터미널 …

        var l10nKey: L10nKey {
            switch self {
            case .zone: return .lensZone
            case .harness: return .lensHarness
            case .runtime: return .lensRuntime
            }
        }
    }

    var groupLens: GroupLens {
        GroupLens(rawValue: spec?.groupBy ?? "") ?? .zone
    }

    /// 현재 보드 뿌리 — 드릴인 > 스펙 rootID > 호스트.
    var effectiveRoot: VNode {
        if let last = roomPath.last { return last }
        if let rootID = spec?.rootID, let found = world.host.find(rootID) { return found }
        return world.host
    }

    /// 노드의 그룹 키 — 실데이터에서만 도출, 모르면 "미기록"(부재의 가시화).
    func groupKey(of node: VNode) -> String {
        switch groupLens {
        case .zone:
            return ""   // FlowerLayout 이 구역 트리로 처리
        case .harness:
            if let key = node.agentKey, let agent = world.agents[key] { return agent.tool }
            let toolSet = Set(node.attachments.flatMap { $0.tools ?? [] })
            guard toolSet.isEmpty else { return toolSet.sorted().joined(separator: "+") }
            return "?"
        case .runtime:
            guard let path = node.leaseDetail else { return "?" }
            if path.contains("/orca/") { return "orca" }
            if path.contains("/.worktrees/") || path.contains("/worktrees/") { return "worktree" }
            return "home"
        }
    }

    func setZoom(_ value: CGFloat) {
        zoom = min(4, max(0.12, value))
    }

    func setTilt(_ value: CGFloat) {
        tilt = min(0.95, max(0, value))
    }

    func setYaw(_ value: CGFloat) {
        var wrapped = value.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        yaw = wrapped
    }

    func nudgeYaw(_ delta: CGFloat) {
        setYaw(yaw + delta)
    }

    // BOARD-PAN-PACK-MARKER
    func fitToViewport(content: CGSize, viewport: CGSize) {
        guard content.width > 1, content.height > 1, viewport.width > 1, viewport.height > 1 else { return }
        let scale = min(viewport.width / content.width, viewport.height / content.height) * 0.92
        setZoom(min(1, scale))
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        loadSpecs()
        let snapshot = await SnapshotBuilder().build()
        world = SnapshotAdapter.vworld(from: snapshot)
        rebindPath()
        focusFirstPersonHome()
        t = timeWindow.upperBound
        if let url = try? SnapshotArchive().record(snapshot) {
            _ = url
        }
        if let pair = SnapshotArchive().latestPair() {
            compareDiff = SnapshotDiffing.diff(old: pair.older.root, new: pair.newer.root)
        }
        lastRefresh = Date()
        tick += 1
    }

    func operate(_ mutation: RoomMutation) async {
        let result = await RoomMutationService().perform(mutation)
        lastOperateOK = result.ok
        lastOperate = result.ok
            ? (result.stdout.isEmpty ? result.command : result.stdout)
            : (result.stderr.isEmpty ? "exit \(result.exitCode): \(result.command)" : result.stderr)
        await refresh()
    }

    func loadAX(appName: String) async {
        axApp = appName
        let result = await OccupancyAX().see(appName: appName)
        axText = result.text
        tick += 1
    }

    func loadSpanSource(_ span: VTraceEvent) {
        guard let path = span.sourcePath, !path.isEmpty else {
            spanExcerpts = []
            return
        }
        spanExcerpts = TranscriptLookup().excerpts(sourcePath: path, around: span.t)
    }

    func parent(of node: VNode) -> VNode? {
        func walk(_ current: VNode) -> VNode? {
            if current.children.contains(where: { $0.id == node.id }) { return current }
            for child in current.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(world.host)
    }

    func defaultOccupant() -> String {
        HostIdentity.occupantLabel()
    }

    /// 고른 테넌트 자리의 workdir. GUI 프로세스 cwd를 도메인으로 쓰지 않는다.
    func defaultWorkdir() -> String {
        let tid = selectedTenantID ?? world.currentTenantID
        func walk(_ node: VNode) -> String? {
            if node.kindRaw == "seat",
               tid == nil || node.tenantID == tid,
               let path = node.leaseDetail, !path.isEmpty {
                return path
            }
            for child in node.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(world.host) ?? ""
    }

    func selectTenant(_ id: String?) {
        selectedTenantID = id
        roomPath = []
        chainFocus = nil
        selected = nil
        focusFirstPersonHome()
        tick += 1
    }

    /// 층 쪼개기는 하지 않는다. 한 화면 그리드가 정본이다.
    func focusFirstPersonHome() {
        roomPath = []
        chainFocus = nil
    }

    /// 한 화면에 붙일 방. 스킬 빈·존 껍데기는 펼치지 않는다.
    var floorNodes: [VNode] {
        _ = tick
        var out: [VNode] = []
        var seen = Set<String>()
        func consider(_ node: VNode) {
            guard isVisible(node), seen.insert(node.id).inserted else { return }
            out.append(node)
        }
        func walk(_ node: VNode) {
            guard isVisible(node) else { return }
            switch node.kindRaw {
            case "room":
                if node.state != .done { consider(node) }
            default:
                for child in node.children { walk(child) }
            }
        }
        walk(world.host)
        return out.sorted { a, b in
            func rank(_ node: VNode) -> (Int, Int, String) {
                let kind: Int
                switch node.kindRaw {
                case "placement", "room": kind = 0
                case "seat": kind = 1
                default: kind = 2
                }
                let empty = node.agentKey == nil ? 1 : 0
                return (kind, empty, node.name)
            }
            return rank(a) < rank(b)
        }
    }

    func findNamed(_ name: String) -> VNode? {
        func walk(_ node: VNode) -> VNode? {
            if node.id == name || node.name == name { return node }
            for child in node.children {
                if let found = walk(child) { return found }
            }
            return nil
        }
        return walk(world.host)
    }

    /// VIEW-SPEC-RESTORE-MARKER
    private func loadSpecs() {
        viewSpecs = ViewSpecStore().loadOrSeed()
        if !viewSpecs.contains(where: { $0.id == currentSpecID }), let first = viewSpecs.first {
            currentSpecID = first.id
        }
    }

    /// 스냅샷이 새 VNode 를 만들므로 id 로 다시 붙인다.
    private func rebindPath() {
        roomPath = roomPath.compactMap { world.host.find($0.id) }
        if let focus = chainFocus {
            chainFocus = world.host.find(focus.id)
        }
        if let sel = selected {
            selected = world.host.find(sel.id)
        }
    }

    func selectSpec(_ id: String) {
        guard viewSpecs.contains(where: { $0.id == id }) else { return }
        currentSpecID = id
        roomPath = []
        chainFocus = nil
        selected = nil
        tick += 1
    }

    func enterRoom(_ node: VNode) {
        guard !node.children.isEmpty else { return }
        if roomPath.last?.id == node.id { return }
        roomPath.append(node)
        chainFocus = nil
        selected = nil
        tick += 1
    }

    /// `to == nil` 이면 스펙 뿌리까지. 인덱스면 그 층까지 남긴다.
    func leaveRoom(to index: Int?) {
        if let index, index >= 0, index < roomPath.count {
            roomPath = Array(roomPath.prefix(index + 1))
        } else {
            roomPath = []
        }
        chainFocus = nil
        selected = nil
        tick += 1
    }

    func passesFilter(_ node: VNode) -> Bool {
        guard let filter = spec?.filter else { return true }
        // zone 컨테이너는 kinds 를 건너뛴다 — 군집 골격이 필터에 무너지면 안 된다.
        if node.kindRaw != "zone" {
            if let kinds = filter.kinds, !kinds.isEmpty, !kinds.contains(node.kindRaw) {
                return false
            }
        }
        if let states = filter.states, !states.isEmpty, node.kindRaw != "zone" {
            if !states.contains(node.state.rawValue) { return false }
        }
        if let hours = filter.bornWithinHours, node.kindRaw != "zone" {
            let born = world.born[node.id] ?? 0
            let cutoff = Date().timeIntervalSince1970 - hours * 3600
            if born < cutoff { return false }
        }
        return true
    }

    func autoRefreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            await refresh()
        }
    }

    func select(node: VNode) {
        selectedSpan = nil
        selected = node
        if let appName = node.leaseName, !appName.isEmpty {
            Task { await loadAX(appName: appName) }
        }
        if let path = node.attachments.first(where: { $0.kind == "transcript" })?.value, !path.isEmpty {
            spanExcerpts = TranscriptLookup().excerpts(sourcePath: path, around: nil)
        }
    }

    func dropSkill(onto node: VNode, skill: String) async {
        let slug = node.blueprint.isEmpty ? nil : node.blueprint
        guard let slug else {
            lastOperateOK = false
            lastOperate = "이 칸에는 설계도 slug가 없어 스킬을 붙일 수 없다"
            tick += 1
            return
        }
        await operate(.attachSkill(slug: slug, tool: skill))
    }

    func select(span: VTraceEvent) {
        selected = nil
        selectedSpan = span
        loadSpanSource(span)
    }

    /// 시점 창 — born 실시각(epoch)에서 역산. 하드코딩 0~10 축 금지.
    var timeWindow: ClosedRange<Double> {
        let now = Date().timeIntervalSince1970
        let borns = world.born.values.filter { $0 > 0 }
        guard let earliest = borns.min(), earliest < now else { return (now - 3600) ... now }
        return earliest ... now
    }

    func switchMode(_ newMode: Mode) {
        mode = newMode
        t = timeWindow.upperBound
        selected = nil
        selectedSpan = nil
    }

    func isVisible(_ node: VNode) -> Bool {
        if mode == .trace && (world.born[node.id] ?? 0) > t { return false }
        if let want = selectedTenantID, let tid = node.tenantID, tid != want {
            return false
        }
        if node.kindRaw != "host" {
            if viewpoint == .first, node.tenantID == nil, node.viewpoint == "third" {
                return false
            }
            if let vp = node.viewpoint, vp != viewpoint.rawValue {
                return false
            }
        }
        return passesFilter(node)
    }

}
