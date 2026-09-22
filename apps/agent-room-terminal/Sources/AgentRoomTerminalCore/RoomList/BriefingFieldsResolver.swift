import Foundation

public struct BriefingFields: Equatable, Sendable {
    public var task: String
    public var verdict: String
    public var writePaths: String
    public var tools: String
    public var sandboxBackend: String

    public init(task: String, verdict: String, writePaths: String, tools: String, sandboxBackend: String = "seatbelt") {
        self.task = task
        self.verdict = verdict
        self.writePaths = writePaths
        self.tools = tools
        self.sandboxBackend = sandboxBackend
    }
}

public struct BriefingInput: Sendable {
    public var task: String
    public var slug: String
    public var verdict: String
    public var allowWrite: [String]
    public var toolbelt: [String]
    public var preset: RoomWallPreset
    public var noneText: String
    public var hostPathText: String
    public var sandboxBackend: String

    public init(
        task: String,
        slug: String,
        verdict: String,
        allowWrite: [String],
        toolbelt: [String],
        preset: RoomWallPreset,
        noneText: String,
        hostPathText: String,
        sandboxBackend: String = "seatbelt"
    ) {
        self.task = task
        self.slug = slug
        self.verdict = verdict
        self.allowWrite = allowWrite
        self.toolbelt = toolbelt
        self.preset = preset
        self.noneText = noneText
        self.hostPathText = hostPathText
        self.sandboxBackend = sandboxBackend
    }
}

public enum BriefingFieldsResolver {
    public static func resolve(
        input: BriefingInput,
        defaultToolsText: String
    ) -> BriefingFields {
        let resolvedTask = input.task.isEmpty ? input.slug : input.task
        let resolvedWritePaths: String
        if input.allowWrite.isEmpty {
            resolvedWritePaths = input.noneText
        } else {
            resolvedWritePaths = input.allowWrite.joined(separator: ", ")
        }
        let resolvedTools: String
        if !input.toolbelt.isEmpty {
            resolvedTools = input.toolbelt.joined(separator: ", ")
        } else if input.preset == .open {
            resolvedTools = input.hostPathText
        } else {
            resolvedTools = defaultToolsText
        }
        return BriefingFields(
            task: resolvedTask,
            verdict: input.verdict,
            writePaths: resolvedWritePaths,
            tools: resolvedTools,
            sandboxBackend: input.sandboxBackend
        )
    }
}
