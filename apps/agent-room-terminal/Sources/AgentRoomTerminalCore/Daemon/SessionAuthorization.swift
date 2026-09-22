import Foundation

/// Identity used by `SessionAuthorizer.allows(requester:target:)`.
public struct SessionPrincipal: Equatable, Sendable {
    public var sessionID: String?
    public var roomDir: String?
    public var authority: String?

    public init(sessionID: String? = nil, roomDir: String? = nil, authority: String? = nil) {
        self.sessionID = sessionID
        self.roomDir = roomDir
        self.authority = authority
    }

    public static func commandRoom(sessionID: String? = nil) -> SessionPrincipal {
        SessionPrincipal(sessionID: sessionID, authority: "commandRoom")
    }
}

/// Single authorization gate for every daemon op.
public enum SessionAuthorizer {
    public static let commandRoomAuthority = "commandRoom"
    public static let foreignRoomError = "foreignRoom"

    /// Command-room authority is allowed everywhere. Otherwise the requester
    /// session's room must be the target room or a parent that opened it
    /// (`…/children/…`).
    public static func allows(requester: SessionPrincipal, target: SessionPrincipal) -> Bool {
        if requester.authority == commandRoomAuthority {
            return true
        }
        guard let requesterRoom = requester.roomDir, let targetRoom = target.roomDir else {
            return false
        }
        return roomAllows(sessionRoomDir: requesterRoom, targetRoomDir: targetRoom)
    }

    public static func roomAllows(sessionRoomDir: String, targetRoomDir: String) -> Bool {
        let session = standardized(sessionRoomDir)
        let target = standardized(targetRoomDir)
        if session == target {
            return true
        }
        let prefix = session.hasSuffix("/") ? session + "children/" : session + "/children/"
        return target.hasPrefix(prefix)
    }

    public static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Path-only helper kept for call sites that already resolved directories.
public enum SessionAuthorization {
    public static func allows(sessionRoomDir: String, targetRoomDir: String) -> Bool {
        SessionAuthorizer.roomAllows(sessionRoomDir: sessionRoomDir, targetRoomDir: targetRoomDir)
    }

    public static func standardized(_ path: String) -> String {
        SessionAuthorizer.standardized(path)
    }
}
