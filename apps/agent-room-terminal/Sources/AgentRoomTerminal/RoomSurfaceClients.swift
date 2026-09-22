import Foundation
import AgentRoomTerminalCore
import CommandKit

/// 화면이 부르는 바깥 CLI(agent-tenant-isolation-manager) 클라이언트.
enum ExclusionReasonLoader {
    static func reasons(
        excludedToolsByRoom: [String: [String]]
    ) -> [String: [String: String]] {
        var cliCache: [String: String] = [:]
        var out: [String: [String: String]] = [:]
        for (roomID, tools) in excludedToolsByRoom {
            var perRoom: [String: String] = [:]
            for cli in tools where !cli.isEmpty {
                if let cached = cliCache[cli] {
                    perRoom[cli] = cached
                    continue
                }
                let reason = reason(for: cli)
                cliCache[cli] = reason
                perRoom[cli] = reason
            }
            out[roomID] = perRoom
        }
        return out
    }

    static func reason(for cli: String) -> String {
        let path = BinaryLocator.find("agent-tenant-isolation-manager") ?? "agent-tenant-isolation-manager"
        let output = CommandKitSync.run(path, ["check", cli, "--json"], timeout: 10)
        if let parsed = RoomSurfaceJSON.complianceReason(from: output.stdout), !parsed.isEmpty {
            return parsed
        }
        let err = output.stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return err
    }
}

enum RoomStandUpClient {
    static func listBlueprints() throws -> [RoomBlueprintPick] {
        []
    }

    static func instantiate(
        slug: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RoomStandUpPlan {
        throw RoomStandUpError.commandFailed("stand-up via external CLI is deprecated")
    }
}

enum RoomStandUpError: Error, Equatable, LocalizedError {
    case commandFailed(String)
    case roomIDMissing
    case blueprintMissing(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let stderr):
            return stderr.isEmpty ? "stand-up failed" : stderr
        case .roomIDMissing:
            return "instantiate returned no room id"
        case .blueprintMissing(let slug):
            return "blueprint missing: \(slug)"
        }
    }
}
