import Foundation

enum RoomJSONFile {
    struct Document: Codable, Equatable, Sendable {
        var id: String
        var slug: String
        var tenant: String
        var layoutId: String
        var parentRoomID: String
        var preset: RoomWallPreset
        var task: String
        var verdict: String
        var brief: [String]
        var toolbelt: [String]
        var walls: RoomWallSnapshot
        var budget: RoomBudgetSnapshot
        var excludedTools: [String]
        var staleTools: [String]

        enum CodingKeys: String, CodingKey {
            case id, slug, tenant, layoutId, parentRoomID, preset, task, verdict
            case brief, toolbelt, walls, budget, excludedTools, staleTools
        }

        init(
            id: String,
            slug: String,
            tenant: String,
            layoutId: String,
            parentRoomID: String,
            preset: RoomWallPreset,
            task: String,
            verdict: String,
            brief: [String],
            toolbelt: [String],
            walls: RoomWallSnapshot,
            budget: RoomBudgetSnapshot,
            excludedTools: [String],
            staleTools: [String] = []
        ) {
            self.id = id
            self.slug = slug
            self.tenant = tenant
            self.layoutId = layoutId
            self.parentRoomID = parentRoomID
            self.preset = preset
            self.task = task
            self.verdict = verdict
            self.brief = brief
            self.toolbelt = toolbelt
            self.walls = walls
            self.budget = budget
            self.excludedTools = excludedTools
            self.staleTools = staleTools
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            slug = try c.decode(String.self, forKey: .slug)
            tenant = try c.decode(String.self, forKey: .tenant)
            layoutId = try c.decode(String.self, forKey: .layoutId)
            parentRoomID = try c.decode(String.self, forKey: .parentRoomID)
            preset = try c.decode(RoomWallPreset.self, forKey: .preset)
            task = try c.decode(String.self, forKey: .task)
            verdict = try c.decode(String.self, forKey: .verdict)
            brief = try c.decode([String].self, forKey: .brief)
            toolbelt = try c.decode([String].self, forKey: .toolbelt)
            walls = try c.decode(RoomWallSnapshot.self, forKey: .walls)
            budget = try c.decode(RoomBudgetSnapshot.self, forKey: .budget)
            excludedTools = try c.decodeIfPresent([String].self, forKey: .excludedTools) ?? []
            staleTools = try c.decodeIfPresent([String].self, forKey: .staleTools) ?? []
        }
    }

    static func write(
        spec: RoomAssemblySpec,
        roomURL: URL,
        excluded: [String],
        staleTools: [String]
    ) throws {
        let document = Document(
            id: spec.roomID,
            slug: spec.slug,
            tenant: spec.tenantID,
            layoutId: spec.layoutID,
            parentRoomID: spec.parent?.roomID ?? "",
            preset: spec.blueprint.preset,
            task: spec.blueprint.task,
            verdict: spec.blueprint.verdict,
            brief: spec.blueprint.brief,
            toolbelt: spec.blueprint.toolbelt,
            // ROOM.json 의 벽은 프리셋·toolbelt 까지 반영한 컴파일 입력(makeWalls)이다 — 스냅샷(writePaths·network)만 쓰면 open 방이 restricted 로 기록된다.
            walls: spec.blueprint.makeWalls(),
            budget: spec.budget,
            excludedTools: excluded,
            staleTools: staleTools
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        let url = roomURL.appendingPathComponent("ROOM.json")
        try writeReadOnly(data: data, to: url)
    }

    static func writeReadOnly(data: Data, to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try fm.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
    }
}

public enum RoomFolder {
    public static func assemble(spec: RoomAssemblySpec) throws -> RoomAssemblyResult {
        try RoomSlug.validate(spec.slug)
        if let parent = spec.parent {
            try RoomNesting.validate(parent: parent, child: spec)
        }
        let baseBin = try BaseBinFolder.ensure(
            environment: spec.environment,
            homeDirectory: spec.homeDirectory,
            selfCLIPath: spec.selfCLIPath
        )
        let roomURL = RoomPaths.directory(for: spec)
        try RoomDirectoryLayout.create(at: roomURL)
        let binPlan = try RoomBinPlanner.plan(spec: spec, baseBin: baseBin)
        if let parent = spec.parent {
            try RoomNesting.validateBinSubset(child: binPlan.names, parent: parent)
        }
        try RoomBinFolder.apply(
            plan: binPlan,
            at: roomURL.appendingPathComponent("bin", isDirectory: true)
        )
        try RoomEnvFile.write(spec: spec, roomURL: roomURL, baseBin: baseBin)
        try RoomMarkdown.write(spec: spec, roomURL: roomURL)
        try RoomJSONFile.write(
            spec: spec,
            roomURL: roomURL,
            excluded: binPlan.excluded,
            staleTools: binPlan.staleTools
        )
        return RoomAssemblyResult(
            roomURL: roomURL,
            excludedTools: binPlan.excluded,
            linkedTools: binPlan.names.sorted()
        )
    }
}
