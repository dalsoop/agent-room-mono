import Foundation

public enum RoomSessionRole: String, Codable, Sendable, Equatable {
    case predecessor
    case successor
}

public struct TerminalSessionInfo: Codable, Sendable, Equatable {
    public var sessionID: String
    public var roomDir: String
    public var pgid: Int32
    public var sessionRole: String

    public init(
        sessionID: String,
        roomDir: String,
        pgid: Int32,
        sessionRole: String = RoomSessionRole.predecessor.rawValue
    ) {
        self.sessionID = sessionID
        self.roomDir = roomDir
        self.pgid = pgid
        self.sessionRole = sessionRole
    }
}

public enum ShellLaunch {
    public static func parse(_ shell: String) -> (executable: String, arguments: [String]) {
        let parts = shell.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.isEmpty {
            return (AppPaths.zsh, ["-r"])
        }
        if parts[0] == "zsh" || parts[0].hasSuffix("/zsh") {
            let args = Array(parts.dropFirst())
            return (AppPaths.zsh, args)
        }
        return (parts[0], Array(parts.dropFirst()))
    }
}
