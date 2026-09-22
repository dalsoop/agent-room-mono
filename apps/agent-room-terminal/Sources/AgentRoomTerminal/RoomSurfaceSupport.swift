import Foundation
import AgentRoomTerminalCore
import RoomKit

struct RoomBlueprintPick: Equatable, Identifiable, Sendable {
    var slug: String
    var title: String
    var task: String
    var verdict: String
    var brief: [String]
    var toolbelt: [String]
    var preset: String
    var writePaths: [String]
    var network: NetworkWall

    var id: String { slug }
}

struct RoomStandUpPlan: Equatable, Sendable {
    var planID: String
    var roomID: String
    var slug: String
    var tenant: String
}

enum RoomSurfaceJSON {
    // 여는 중괄호·대괄호를 문자 리터럴로 쓰지 않는다 — lint 의 괄호 계수기가 문자열 안 괄호를 센다.
    static let objectOpen = Character(UnicodeScalar(0x7B))
    static let arrayOpen = Character(UnicodeScalar(0x5B))

    /// 설치본 경고가 앞에 붙은 stdout 에서 첫 JSON 값부터 파싱한다. 실패는 빈 목록 — 호출자가 배너로 알린다.
    static func objects(from stdout: String) -> [Any] {
        guard let start = stdout.firstIndex(of: objectOpen) ?? stdout.firstIndex(of: arrayOpen) else {
            return []
        }
        let blob = String(stdout[start...])
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: Data(blob.utf8))
        } catch {
            return []
        }
        if let array = raw as? [Any] { return array }
        guard let dict = raw as? [String: Any] else { return [] }
        if let payload = dict["payload"] {
            if let array = payload as? [Any] { return array }
            if let object = payload as? [String: Any] { return [object] }
        }
        if let result = dict["result"] {
            if let array = result as? [Any] { return array }
            if let object = result as? [String: Any] { return [object] }
        }
        return [dict]
    }

    static func standingOrScheduledBlueprints(from stdout: String) -> [RoomBlueprintPick] {
        objects(from: stdout).compactMap { item -> RoomBlueprintPick? in
            guard let dict = item as? [String: Any] else { return nil }
            let slug = string(dict["slug"]) ?? ""
            guard !slug.isEmpty, isStandingOrScheduled(slug: slug, nature: dict["nature"]) else {
                return nil
            }
            let walls = dict["walls"] as? [String: Any] ?? [:]
            return RoomBlueprintPick(
                slug: slug,
                title: string(dict["title"]) ?? slug,
                task: string(dict["task"]) ?? slug,
                verdict: verdictString(dict["verdict"]),
                brief: stringArray(dict["brief"]),
                toolbelt: stringArray(dict["toolbelt"]),
                preset: string(dict["wallPreset"]) ?? "toolbelt",
                writePaths: stringArray(walls["writePaths"]),
                network: NetworkWall.parse(walls["network"]) ?? .open
            )
        }
    }

    static func isStandingOrScheduled(slug: String, nature: Any?) -> Bool {
        if slug == "command-room" { return true }
        if let name = nature as? String {
            return name == "standing" || name == "scheduled"
        }
        guard let dict = nature as? [String: Any] else { return false }
        return dict["standing"] != nil || dict["scheduled"] != nil
    }

    static func standUpPlan(from stdout: String, slug: String, tenant: String) -> RoomStandUpPlan? {
        guard let plan = objects(from: stdout).first as? [String: Any] else { return nil }
        let planID = string(plan["id"]) ?? ""
        let rooms = plan["rooms"] as? [[String: Any]] ?? []
        let first = rooms.first
        let roomID = string(first?["id"]) ?? string(plan["roomID"]) ?? ""
        let resolvedSlug = string(first?["blueprintSlug"]) ?? slug
        let resolvedTenant = string(plan["tenantID"]) ?? tenant
        guard !planID.isEmpty, !roomID.isEmpty else { return nil }
        return RoomStandUpPlan(
            planID: planID,
            roomID: roomID,
            slug: resolvedSlug,
            tenant: resolvedTenant
        )
    }

    static func complianceReason(from stdout: String) -> String? {
        guard let object = objects(from: stdout).first as? [String: Any] else { return nil }
        if let reason = string(object["reason"]) { return reason }
        if let nested = object["result"] as? [String: Any], let reason = string(nested["reason"]) {
            return reason
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let uuid = value as? NSNumber { return uuid.stringValue }
        return nil
    }

    static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    static func verdictString(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let dict = value as? [String: Any] {
            if let command = dict["command"] as? String { return command }
            if let wrapped = dict["command"] as? [String: Any],
               let command = wrapped["_0"] as? String {
                return command
            }
            if let slug = dict["reviewRoom"] as? String { return slug }
            if let slug = dict["blueprintSlug"] as? String { return slug }
        }
        return "true"
    }
}

enum RoomActionBinding {
    static func planID(folder: URL, layoutId: String) -> String {
        if !layoutId.isEmpty { return layoutId }
        let parentName = folder.deletingLastPathComponent().lastPathComponent
        if parentName != RoomPaths.roomsDirectoryName {
            return parentName
        }
        return ""
    }

    static func occupant(tool: AgentRoomTool = .claude) -> String {
        let host = AgentOccupant.shortHost().lowercased()
        return "agent:\(tool.rawValue)@\(host)"
    }

    static func context(
        folder: URL,
        document: RoomDocument,
        sessionID: String?,
        environment: [String: String]
    ) -> RoomActionContext {
        let plan = planID(folder: folder, layoutId: document.layoutId)
        let session = sessionID ?? ""
        let occupant = RoomActionBinding.occupant()
        let spec = makeSpec(
            roomID: document.id,
            slug: document.slug,
            tenant: document.tenant,
            layoutID: plan,
            pick: RoomBlueprintPick(
                slug: document.slug,
                title: document.slug,
                task: document.task,
                verdict: document.verdict,
                brief: document.brief,
                toolbelt: document.toolbelt,
                preset: document.preset.rawValue,
                writePaths: document.walls.writePaths,
                network: document.walls.network
            ),
            budget: document.budget,
            environment: environment
        )
        return makeContext(
            spec: spec,
            roomURL: folder,
            sessionID: session,
            planID: plan,
            occupant: occupant,
            wallMode: "full",
            handoffID: latestHandoffID(in: folder),
            budget: budgetState(from: document.budget)
        )
    }

    static func context(
        plan: RoomStandUpPlan,
        pick: RoomBlueprintPick,
        environment: [String: String]
    ) -> RoomActionContext {
        let budget = computedBudget()
        let spec = makeSpec(
            roomID: plan.roomID,
            slug: plan.slug,
            tenant: plan.tenant,
            layoutID: plan.planID,
            pick: pick,
            budget: budgetSnapshot(from: budget),
            environment: environment
        )
        let roomURL = roomURL(spec: spec, environment: environment)
        return makeContext(
            spec: spec,
            roomURL: roomURL,
            sessionID: "",
            planID: plan.planID,
            occupant: RoomActionBinding.occupant(),
            wallMode: "full",
            handoffID: "",
            budget: budget
        )
    }

    static func tenantSlugs(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let home = AppPaths.stateRoot(environment: environment).path
        let root = RoomPaths.tenantsRoot(environment: environment, homeDirectory: home)
        // allow:silent-error-swallow — 테넌트 루트가 아직 없으면 빈 목록이 맞다
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { !$0.hasPrefix("_") && !$0.hasPrefix(".") }.sorted()
    }

    static func roomURL(
        roomID: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let home = AppPaths.stateRoot(environment: environment).path
        return RoomPathResolver.resolveRoomURL(
            roomID: roomID,
            tenant: tenant,
            environment: environment,
            homeDirectory: home
        )
    }

    static func roomURL(spec: RoomAssemblySpec, environment: [String: String]) -> URL {
        roomURL(
            roomID: spec.roomID,
            tenant: spec.tenantSlug,
            environment: environment
        )
    }

    private static func makeSpec(
        roomID: String,
        slug: String,
        tenant: String,
        layoutID: String,
        pick: RoomBlueprintPick,
        budget: RoomBudgetSnapshot,
        environment: [String: String]
    ) -> RoomAssemblySpec {
        let home = AppPaths.stateRoot(environment: environment).path
        let preset = RoomWallPreset(rawValue: pick.preset) ?? .toolbelt
        let clean = tenant.hasPrefix("tenant:") ? String(tenant.dropFirst(7)) : tenant
        return RoomAssemblySpec(
            roomID: roomID,
            slug: slug,
            tenantSlug: tenant,
            layoutID: layoutID,
            blueprint: RoomBlueprintSnapshot(
                task: pick.task,
                verdict: pick.verdict,
                brief: pick.brief,
                toolbelt: pick.toolbelt,
                preset: preset,
                walls: RoomWallSnapshot(writePaths: pick.writePaths, network: pick.network)
            ),
            tenantPolicy: RoomTenantPolicy(
                stateRoot: RoomPaths.tenantStateRoot(
                    tenant: tenant,
                    environment: environment,
                    homeDirectory: home
                ).path,
                wikiWorld: "tenant-\(clean)"
            ),
            budget: budget,
            compliance: TenantIsolationComplianceChecker(environment: environment),
            environment: environment,
            homeDirectory: home,
            selfCLIPath: CommandLine.arguments.first
        )
    }

    private static func makeContext(
        spec: RoomAssemblySpec,
        roomURL: URL,
        sessionID: String,
        planID: String,
        occupant: String,
        wallMode: String,
        handoffID: String,
        budget: BudgetState
    ) -> RoomActionContext {
        let authority = LedgerAuthority.commandRoom(
            sessionID: sessionID.isEmpty ? "gui" : sessionID,
            seatedRoomID: spec.roomID
        )
        let shell = spec.blueprint.preset == .open ? "zsh" : "zsh -r"
        let handoff = HandoffRequest(
            roomID: spec.roomID,
            roomURL: roomURL,
            planID: planID,
            note: "",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: budget,
            occupant: occupant,
            successorOccupant: occupant,
            successorHandle: RoomOpenPolicy.successorHandle(sessionID: sessionID),
            sessionID: sessionID,
            wallMode: wallMode,
            authority: authority
        )
        return RoomActionContext(
            spec: spec,
            roomURL: roomURL,
            envFile: roomURL.appendingPathComponent("env").path,
            shell: shell,
            seatbeltProfile: RoomOpenPolicy.seatbeltProfile(
                preset: spec.blueprint.preset,
                roomPath: roomURL.path,
                writePaths: spec.blueprint.walls.writePaths,
                network: spec.blueprint.walls.network,
                agentTools: spec.blueprint.agentTools,
                workdir: spec.blueprint.workdir
            ),
            sessionID: sessionID,
            planID: planID,
            occupant: occupant,
            wallMode: wallMode,
            authority: authority,
            handoff: handoff,
            handoffID: handoffID
        )
    }

    private static func latestHandoffID(in folder: URL) -> String {
        let dir = folder.appendingPathComponent("handoff", isDirectory: true)
        // allow:silent-error-swallow — handoff/ 폴더가 없으면 빈병 없음
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
            .last ?? ""
    }

    private static func computedBudget() -> BudgetState {
        Budget.compute(
            tool: .claude,
            initialInput: 0,
            used: nil,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil
        )
    }

    private static func budgetSnapshot(from budget: BudgetState) -> RoomBudgetSnapshot {
        RoomBudgetSnapshot(
            window: budget.window,
            trigger: budget.trigger,
            initialInput: budget.initialInput,
            reservedOutput: budget.reservedOutput,
            usable: budget.usable,
            handoffAt: budget.handoffAt
        )
    }

    private static func budgetState(from snapshot: RoomBudgetSnapshot) -> BudgetState {
        BudgetState(
            window: snapshot.window,
            trigger: snapshot.trigger,
            initialInput: snapshot.initialInput,
            reservedOutput: snapshot.reservedOutput,
            usable: snapshot.usable,
            used: nil,
            handoffAt: snapshot.handoffAt,
            elapsedMinutes: nil,
            estimatedWorkMinutes: nil,
            state: .unknown
        )
    }
}
