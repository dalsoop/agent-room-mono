import Foundation
import AgentRoomTerminalCore

public enum SeatbeltLaunchError: Error, LocalizedError, Equatable, Sendable {
    case sandboxUnavailable

    public var errorDescription: String? {
        switch self {
        case .sandboxUnavailable:
            return "sandbox-exec is unavailable on this host"
        }
    }
}

enum SeatbeltLaunch {
    static func command(
        shell: String,
        profile: String?
    ) throws -> (executable: String, arguments: [String]) {
        let parsed = ShellLaunch.parse(shell)
        guard let profile, !profile.isEmpty else {
            return parsed
        }
        let sandbox = AppPaths.sandboxExec
        let available = AppPaths.isSandboxAvailable
        guard available else {
            throw SeatbeltLaunchError.sandboxUnavailable
        }
        var arguments = ["-p", profile]
        arguments.append(parsed.executable)
        arguments.append(contentsOf: parsed.arguments)
        return (sandbox, arguments)
    }
}
