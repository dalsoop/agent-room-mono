import Foundation

enum TranscriptBudgetPresence {
    case noBinding
    case toolUnsupported
    case noTranscript
    case measured

    static func classify(_ bindings: [TranscriptBinding], files: any RoomFileIO) -> TranscriptBudgetPresence {
        switch bindings.isEmpty {
        case true:
            return .noBinding
        case false:
            return classifyNonEmpty(bindings, files: files)
        }
    }

    static func usage(
        bindings: [TranscriptBinding],
        used: Int?,
        handoffAt: Int,
        files: any RoomFileIO
    ) -> RoomUsage {
        switch classify(bindings, files: files) {
        case .noBinding:
            return RoomUsage(used: nil, handoffAt: handoffAt, unknownReason: UnknownBudgetReason.noBinding)
        case .toolUnsupported:
            return RoomUsage(used: nil, handoffAt: handoffAt, unknownReason: UnknownBudgetReason.toolUnsupported)
        case .noTranscript:
            return RoomUsage(used: nil, handoffAt: handoffAt, unknownReason: UnknownBudgetReason.noTranscript)
        case .measured:
            return RoomUsage(used: used ?? 0, handoffAt: handoffAt)
        }
    }

    private static func classifyNonEmpty(
        _ bindings: [TranscriptBinding],
        files: any RoomFileIO
    ) -> TranscriptBudgetPresence {
        switch isUnsupported(bindings) {
        case true:
            return .toolUnsupported
        case false:
            return classifyFiles(bindings, files: files)
        }
    }

    private static func isUnsupported(_ bindings: [TranscriptBinding]) -> Bool {
        bindings.contains { binding in
            binding.reason == TranscriptBindingReason.toolUnsupported && binding.path.isEmpty
        }
    }

    private static func classifyFiles(
        _ bindings: [TranscriptBinding],
        files: any RoomFileIO
    ) -> TranscriptBudgetPresence {
        switch bindings.contains(where: { files.fileExists(atPath: $0.path) }) {
        case true:
            return .measured
        case false:
            return .noTranscript
        }
    }
}
