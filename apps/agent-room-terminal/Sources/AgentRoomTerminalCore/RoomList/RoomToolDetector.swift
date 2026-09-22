import Foundation

public enum RoomToolDetector {
    public static func detect(roomURL: URL, occupants: [RoomOccupant]) -> AgentRoomTool {
        ToolAuthReadinessPolicy.resolveOccupantTool(roomURL: roomURL, occupants: occupants) ?? .claude
    }

    public static func normalizeToolName(_ rawName: String) -> AgentRoomTool? {
        AgentRoomTool.normalizeName(rawName)
    }

    private static func stripPrefix(_ candidate: String) -> String {
        guard candidate.hasPrefix("agent:") else { return candidate }
        return String(candidate.dropFirst("agent:".count))
    }

    public static func parseToolFromHandle(_ handle: String) -> AgentRoomTool? {
        let stripped = stripPrefix(handle.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !stripped.isEmpty else { return nil }
        let tokens = stripped.components(separatedBy: CharacterSet(charactersIn: "@ "))
        return normalizeToolName(tokens.first ?? stripped)
    }

    public static func needsCredentialCheck(tool: AgentRoomTool) -> Bool {
        ToolAuthReadinessPolicy.requiresAuthCheck(for: tool)
    }

    public static func isCredentialSeeded(
        tool: AgentRoomTool,
        roomURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let configDir = AgentCredentialInjector.configDirName(tool: tool, roomURL: roomURL)
        let credentialFile = configDir.appendingPathComponent(".credentials.json")
        return fileManager.fileExists(atPath: credentialFile.path)
    }

    public static func detectFromSpec(roomURL: URL) -> AgentRoomTool? {
        let specURL = roomURL.appendingPathComponent(RoomPaths.specFileName)
        guard let data = try? Data(contentsOf: specURL) else { return nil }
        let spec: RoomSpec
        do {
            spec = try JSONDecoder().decode(RoomSpec.self, from: data)
        } catch {
            return nil
        }
        guard let launch = spec.launch else {
            return nil
        }
        return normalizeToolName(launch.tool.rawValue)
    }
}
