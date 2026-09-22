import Foundation
import RoomKit

public enum SessionAttachError: Error, Equatable, LocalizedError {
    case roomRequired
    case roomNotFound(String)
    case emptySessionID

    public var errorDescription: String? {
        switch self {
        case .roomRequired:
            return "open --attach-session needs --room when the seat has no room"
        case .roomNotFound(let id):
            return "room not found: \(id)"
        case .emptySessionID:
            return "usage: open --attach-session <sessionID> [--room <id>]"
        }
    }
}

public struct SessionAttachRequest: Sendable {
    public var sessionID: String
    public var roomID: String?
    public var environment: [String: String]
    public var homeDirectory: String
    public var files: any RoomFileIO
    public var hooks: SessionAttachHooks

    public init(
        sessionID: String,
        roomID: String? = nil,
        environment: [String: String],
        homeDirectory: String,
        files: any RoomFileIO = FoundationRoomFileIO(),
        hooks: SessionAttachHooks = SessionAttachHooks()
    ) {
        self.sessionID = sessionID
        self.roomID = roomID
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.files = files
        self.hooks = hooks
    }
}

public struct SessionAttachHooks: Sendable {
    public var openPty: (@Sendable () throws -> String)?

    public init(openPty: (@Sendable () throws -> String)? = nil) {
        self.openPty = openPty
    }
}

public struct SessionAttachResult: Equatable, Sendable {
    public var roomID: String
    public var sessionID: String
    public var wallMode: String
    public var transcript: TranscriptBinding
    public var enforcement: String

    public var jsonObject: [String: Any] {
        [
            "roomID": roomID,
            "sessionID": sessionID,
            "wallMode": wallMode,
            "enforcement": enforcement,
            "transcript": [
                "tool": transcript.tool,
                "path": transcript.path,
                "reason": transcript.reason,
            ],
        ]
    }
}

/// 훅만 붙은 세션에 벽을 뒤늦게 등록한다. PTY 를 만들지 않는다.
public enum SessionAttach {
    public static func run(_ request: SessionAttachRequest) throws -> SessionAttachResult {
        refusePty(request.hooks)
        let sessionID = request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else { throw SessionAttachError.emptySessionID }
        let seat = try liveSeat(sessionID: sessionID, request: request)
        let roomID = try resolvedRoomID(request: request, seat: seat)
        let roomURL = try roomURL(roomID: roomID, request: request)
        let tool = resolvedTool(seat: seat)
        let workdir = hostWorkdir(seat: seat, roomURL: roomURL)
        let transcript = TranscriptLocations.resolve(
            tool: tool,
            sessionID: sessionID,
            workdir: workdir,
            homeDirectory: request.homeDirectory,
            environment: request.environment,
            files: request.files,
            seat: seat
        )
        try registerWalls(roomURL: roomURL, sessionID: sessionID, files: request.files)
        if !transcript.path.isEmpty {
            try TranscriptRegistry.register(roomURL: roomURL, tool: tool, path: transcript.path)
        }
        try appendAttached(roomURL: roomURL, sessionID: sessionID, transcript: transcript)
        return SessionAttachResult(
            roomID: roomID,
            sessionID: sessionID,
            wallMode: WallEnforcementScope.wallModeFull,
            transcript: transcript,
            enforcement: WallEnforcementScope.wallsRegisteredOnly
        )
    }

    static func liveSeat(sessionID: String, request: SessionAttachRequest) throws -> SeatTranscriptRecord? {
        let directory = SeatTranscriptStore.directory(
            environment: request.environment,
            homeDirectory: request.homeDirectory
        )
        guard let record = try SeatTranscriptStore.load(
            sessionID: sessionID,
            directory: directory,
            files: request.files
        ) else { return nil }
        return record.isLive ? record : nil
    }

    static func resolvedRoomID(request: SessionAttachRequest, seat: SeatTranscriptRecord?) throws -> String {
        if let flag = request.roomID?.trimmingCharacters(in: .whitespacesAndNewlines), !flag.isEmpty {
            return flag
        }
        if let seat { return seat.seat.roomID.uuidString }
        throw SessionAttachError.roomRequired
    }

    static func refusePty(_ hooks: SessionAttachHooks) {
        _ = hooks.openPty.map { _ in () }
    }

    static func hostWorkdir(seat: SeatTranscriptRecord?, roomURL: URL) -> String {
        let host = seat?.host.workdir ?? ""
        switch host.isEmpty {
        case true: return roomURL.path
        case false: return host
        }
    }

    static func resolvedTool(seat: SeatTranscriptRecord?) -> AgentRoomTool {
        guard let name = seat?.session.tool, let tool = AgentRoomTool(rawValue: name) else {
            return .claude
        }
        return tool
    }

    static func roomURL(roomID: String, request: SessionAttachRequest) throws -> URL {
        let found = try RoomFolderLocator.find(roomID: roomID, environment: request.environment)
        guard let found else { throw SessionAttachError.roomNotFound(roomID) }
        return found
    }

    static func registerWalls(roomURL: URL, sessionID: String, files: any RoomFileIO) throws {
        let walls: RoomWalls
        do {
            walls = try RoomDocument.load(from: roomURL).walls
        } catch {
            walls = RoomWalls()
        }
        let record = WallEnforcementRecord(
            sessionID: sessionID,
            wallMode: WallEnforcementScope.wallModeFull,
            enforcement: WallEnforcementScope.wallsRegisteredOnly,
            walls: walls
        )
        let url = roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent(WallEnforcementScope.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try files.write(try encoder.encode(record), to: url)
    }

    static func appendAttached(roomURL: URL, sessionID: String, transcript: TranscriptBinding) throws {
        let event = RoomEvent(
            kind: "attached",
            by: "agent-room-terminal",
            payload: [
                "sessionID": .string(sessionID),
                "enforcement": .string(WallEnforcementScope.wallsRegisteredOnly),
                "transcript": .string(transcript.path),
            ]
        )
        _ = try RoomEventLog(roomURL: roomURL).append(event)
    }
}

struct WallEnforcementRecord: Codable, Equatable, Sendable {
    var sessionID: String
    var wallMode: String
    var enforcement: String
    var walls: RoomWalls
}
