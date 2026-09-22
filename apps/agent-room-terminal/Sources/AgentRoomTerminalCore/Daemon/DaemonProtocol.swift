import Foundation

public enum DaemonOp: String, Codable, Sendable, Equatable {
    case openSession
    case closeSession
    case exec
    case attach
    case snapshot
    case listSessions
    case tuning
    case input
    case ensureNetworkProxy
    case resize
    case events
}

public struct TerminalDimensions: Codable, Sendable, Equatable {
    public var columns: Int?
    public var rows: Int?

    public init(columns: Int? = nil, rows: Int? = nil) {
        self.columns = columns
        self.rows = rows
    }
}

public struct DaemonEventsParams: Codable, Sendable, Equatable {
    public var since: Int?

    public init(since: Int? = nil) {
        self.since = since
    }
}

public struct DaemonTuningParams: Codable, Sendable, Equatable {
    public var action: String?
    public var key: String?
    public var value: String?

    public init(action: String? = nil, key: String? = nil, value: String? = nil) {
        self.action = action
        self.key = key
        self.value = value
    }
}

public struct DaemonExecParams: Codable, Sendable, Equatable {
    public var timeoutSeconds: Int?
    public var launch: Bool?
    public var raw: Bool?
    public var tool: String?

    public init(timeoutSeconds: Int? = nil, launch: Bool? = nil, raw: Bool? = nil, tool: String? = nil) {
        self.timeoutSeconds = timeoutSeconds
        self.launch = launch
        self.raw = raw
        self.tool = tool
    }
}

public struct DaemonRequest: Codable, Sendable, Equatable {
    public var op: DaemonOp
    public var roomDir: String?
    public var envFile: String?
    public var shell: String?
    public var seatbeltProfile: String?
    public var sessionID: String?
    public var argv: [String]?
    public var lines: Int?
    public var replayBytes: Int?
    public var windowDimensions: TerminalDimensions?
    public var columns: Int? {
        get { windowDimensions?.columns }
        set {
            if windowDimensions != nil {
                windowDimensions?.columns = newValue
            } else if newValue != nil {
                windowDimensions = TerminalDimensions(columns: newValue, rows: nil)
            }
        }
    }
    public var rows: Int? {
        get { windowDimensions?.rows }
        set {
            if windowDimensions != nil {
                windowDimensions?.rows = newValue
            } else if newValue != nil {
                windowDimensions = TerminalDimensions(columns: nil, rows: newValue)
            }
        }
    }
    public var tuningParams: DaemonTuningParams?
    public var tuningAction: String? {
        get { tuningParams?.action }
        set {
            if tuningParams != nil {
                tuningParams?.action = newValue
            } else if newValue != nil {
                tuningParams = DaemonTuningParams(action: newValue)
            }
        }
    }
    public var tuningKey: String? {
        get { tuningParams?.key }
        set {
            if tuningParams != nil {
                tuningParams?.key = newValue
            } else if newValue != nil {
                tuningParams = DaemonTuningParams(key: newValue)
            }
        }
    }
    public var tuningValue: String? {
        get { tuningParams?.value }
        set {
            if tuningParams != nil {
                tuningParams?.value = newValue
            } else if newValue != nil {
                tuningParams = DaemonTuningParams(value: newValue)
            }
        }
    }
    public var input: String?
    /// Base64 payload for attach-stream / `sendInput` writes.
    public var bytes: String?
    /// `"commandRoom"` grants every op. No extra secret — the daemon socket is user-owned.
    public var authority: String?
    /// Requester `ROOM_SESSION` id. Distinct from `sessionID` when that field is the target.
    public var roomSession: String?
    public var execParams: DaemonExecParams?
    public var timeoutSeconds: Int? {
        get { execParams?.timeoutSeconds }
        set {
            if execParams != nil {
                execParams?.timeoutSeconds = newValue
            } else if newValue != nil {
                execParams = DaemonExecParams(timeoutSeconds: newValue)
            }
        }
    }
    /// `predecessor` | `successor`. Omitted by old clients — daemon defaults to predecessor.
    public var sessionRole: String?
    /// `ensureNetworkProxy` 허용 호스트. 생략하면 빈 목록(전부 거부).
    public var allowedDomains: [String]?
    /// 첫 화면에 출력할 배너 문자열(spec 요약 + exit 안내).
    public var banner: String?
    public var launch: Bool? {
        get { execParams?.launch }
        set {
            if execParams != nil {
                execParams?.launch = newValue
            } else if newValue != nil {
                execParams = DaemonExecParams(launch: newValue)
            }
        }
    }
    public var raw: Bool? {
        get { execParams?.raw }
        set {
            if execParams != nil {
                execParams?.raw = newValue
            } else if newValue != nil {
                execParams = DaemonExecParams(raw: newValue)
            }
        }
    }
    public var tool: String? {
        get { execParams?.tool }
        set {
            if execParams != nil {
                execParams?.tool = newValue
            } else if newValue != nil {
                execParams = DaemonExecParams(tool: newValue)
            }
        }
    }
    public var eventsParams: DaemonEventsParams?
    public var since: Int? {
        get { eventsParams?.since }
        set {
            if eventsParams != nil {
                eventsParams?.since = newValue
            } else if newValue != nil {
                eventsParams = DaemonEventsParams(since: newValue)
            }
        }
    }
    /// `exec` 가 verdict 판정 명령인지 여부.
    public var isVerdict: Bool {
        argv?.contains("--verdict") ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case op
        case roomDir
        case envFile
        case shell
        case seatbeltProfile
        case sessionID
        case argv
        case lines
        case replayBytes
        case columns
        case rows
        case tuningAction
        case tuningKey
        case tuningValue
        case input
        case bytes
        case authority
        case roomSession
        case timeoutSeconds
        case sessionRole
        case allowedDomains
        case banner
        case launch
        case raw
        case tool
        case since
    }

    public init(
        op: DaemonOp,
        sessionID: String? = nil,
        lines: Int? = nil,
        replayBytes: Int? = nil,
        columns: Int? = nil,
        rows: Int? = nil,
        input: String? = nil,
        roomSession: String? = nil
    ) {
        self.op = op
        self.sessionID = sessionID
        self.lines = lines
        self.replayBytes = replayBytes
        if columns != nil || rows != nil {
            self.windowDimensions = TerminalDimensions(columns: columns, rows: rows)
        } else {
            self.windowDimensions = nil
        }
        self.input = input
        self.roomSession = roomSession
    }

    public init(
        op: DaemonOp,
        sessionID: String?,
        bytes: String?,
        roomSession: String? = nil
    ) {
        self.op = op
        self.sessionID = sessionID
        self.bytes = bytes
        self.roomSession = roomSession
    }

    public init(
        op: DaemonOp,
        roomDir: String?,
        envFile: String? = nil,
        shell: String? = nil,
        seatbeltProfile: String? = nil,
        sessionRole: String? = nil
    ) {
        self.op = op
        self.roomDir = roomDir
        self.envFile = envFile
        self.shell = shell
        self.seatbeltProfile = seatbeltProfile
        self.sessionRole = sessionRole
    }

    public init(
        op: DaemonOp,
        roomDir: String?,
        sessionID: String?,
        argv: [String]?,
        timeoutSeconds: Int? = nil,
        launch: Bool? = nil
    ) {
        self.op = op
        self.roomDir = roomDir
        self.sessionID = sessionID
        self.argv = argv
        if timeoutSeconds != nil || launch != nil {
            self.execParams = DaemonExecParams(timeoutSeconds: timeoutSeconds, launch: launch)
        }
    }

    public init(
        op: DaemonOp,
        tuningAction: String?,
        tuningKey: String? = nil,
        tuningValue: String? = nil
    ) {
        self.op = op
        self.tuningAction = tuningAction
        self.tuningKey = tuningKey
        self.tuningValue = tuningValue
    }

    public init(
        op: DaemonOp,
        roomDir: String?,
        allowedDomains: [String]?
    ) {
        self.op = op
        self.roomDir = roomDir
        self.allowedDomains = allowedDomains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        op = try container.decode(DaemonOp.self, forKey: .op)
        roomDir = try container.decodeIfPresent(String.self, forKey: .roomDir)
        envFile = try container.decodeIfPresent(String.self, forKey: .envFile)
        shell = try container.decodeIfPresent(String.self, forKey: .shell)
        seatbeltProfile = try container.decodeIfPresent(String.self, forKey: .seatbeltProfile)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        argv = try container.decodeIfPresent([String].self, forKey: .argv)
        lines = try container.decodeIfPresent(Int.self, forKey: .lines)
        replayBytes = try container.decodeIfPresent(Int.self, forKey: .replayBytes)
        let cols = try container.decodeIfPresent(Int.self, forKey: .columns)
        let rowsVal = try container.decodeIfPresent(Int.self, forKey: .rows)
        if cols != nil || rowsVal != nil {
            windowDimensions = TerminalDimensions(columns: cols, rows: rowsVal)
        } else {
            windowDimensions = nil
        }
        tuningAction = try container.decodeIfPresent(String.self, forKey: .tuningAction)
        tuningKey = try container.decodeIfPresent(String.self, forKey: .tuningKey)
        tuningValue = try container.decodeIfPresent(String.self, forKey: .tuningValue)
        input = try container.decodeIfPresent(String.self, forKey: .input)
        bytes = try container.decodeIfPresent(String.self, forKey: .bytes)
        authority = try container.decodeIfPresent(String.self, forKey: .authority)
        roomSession = try container.decodeIfPresent(String.self, forKey: .roomSession)
        let ts = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
        let launchVal = try container.decodeIfPresent(Bool.self, forKey: .launch)
        let rawVal = try container.decodeIfPresent(Bool.self, forKey: .raw)
        let toolVal = try container.decodeIfPresent(String.self, forKey: .tool)
        if ts != nil || launchVal != nil || rawVal != nil || toolVal != nil {
            execParams = DaemonExecParams(timeoutSeconds: ts, launch: launchVal, raw: rawVal, tool: toolVal)
        }
        sessionRole = try container.decodeIfPresent(String.self, forKey: .sessionRole)
        allowedDomains = try container.decodeIfPresent([String].self, forKey: .allowedDomains)
        banner = try container.decodeIfPresent(String.self, forKey: .banner)
        let sinceVal = try container.decodeIfPresent(Int.self, forKey: .since)
        if let sinceVal {
            eventsParams = DaemonEventsParams(since: sinceVal)
        } else {
            eventsParams = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(op, forKey: .op)
        try container.encodeIfPresent(roomDir, forKey: .roomDir)
        try container.encodeIfPresent(envFile, forKey: .envFile)
        try container.encodeIfPresent(shell, forKey: .shell)
        try container.encodeIfPresent(seatbeltProfile, forKey: .seatbeltProfile)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(argv, forKey: .argv)
        try container.encodeIfPresent(lines, forKey: .lines)
        try container.encodeIfPresent(replayBytes, forKey: .replayBytes)
        try container.encodeIfPresent(windowDimensions?.columns, forKey: .columns)
        try container.encodeIfPresent(windowDimensions?.rows, forKey: .rows)
        try container.encodeIfPresent(tuningAction, forKey: .tuningAction)
        try container.encodeIfPresent(tuningKey, forKey: .tuningKey)
        try container.encodeIfPresent(tuningValue, forKey: .tuningValue)
        try container.encodeIfPresent(input, forKey: .input)
        try container.encodeIfPresent(bytes, forKey: .bytes)
        try container.encodeIfPresent(authority, forKey: .authority)
        try container.encodeIfPresent(roomSession, forKey: .roomSession)
        try container.encodeIfPresent(execParams?.timeoutSeconds, forKey: .timeoutSeconds)
        try container.encodeIfPresent(execParams?.launch, forKey: .launch)
        try container.encodeIfPresent(execParams?.raw, forKey: .raw)
        try container.encodeIfPresent(execParams?.tool, forKey: .tool)
        try container.encodeIfPresent(sessionRole, forKey: .sessionRole)
        try container.encodeIfPresent(allowedDomains, forKey: .allowedDomains)
        try container.encodeIfPresent(banner, forKey: .banner)
        try container.encodeIfPresent(since, forKey: .since)
    }
}

public enum DaemonProtocolError: Error, Equatable, Sendable, LocalizedError {
    case requestFailed(String)
    case unexpectedFrame

    /// 데몬이 보낸 거부 사유(예 "restricted room: path execution is not allowed")가 그대로 보인다.
    /// 없으면 "error 0" 처럼 뭉개져 사용자가 왜 막혔는지 모른다(실측 2026-09-03).
    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return "daemon refused: \(message)"
        case .unexpectedFrame:
            return "daemon sent an unexpected frame"
        }
    }
}

/// Length-prefixed JSON frame on an attach stream (first response or later event).
public struct DaemonStreamFrame: Codable, Sendable, Equatable {
    public var ok: Bool?
    public var result: JSONValue?
    public var error: String?
    public var generation: UInt64?
    public var event: String?
    public var sessionID: String?
    public var bytes: String?
    public var code: Int?
    public var roomEvent: RoomEvent?

    public init(
        ok: Bool? = nil,
        result: JSONValue? = nil,
        error: String? = nil,
        generation: UInt64? = nil,
        event: String? = nil,
        sessionID: String? = nil,
        bytes: String? = nil,
        code: Int? = nil,
        roomEvent: RoomEvent? = nil
    ) {
        self.ok = ok
        self.result = result
        self.error = error
        self.generation = generation
        self.event = event
        self.sessionID = sessionID
        self.bytes = bytes
        self.code = code
        self.roomEvent = roomEvent
    }

    public var outputBytes: Data? {
        guard let bytes else { return nil }
        return Data(base64Encoded: bytes)
    }

    enum CodingKeys: String, CodingKey {
        case ok, result, error, generation, event, sessionID, bytes, code, roomEvent
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ok, forKey: .ok)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(generation, forKey: .generation)
        try container.encodeIfPresent(event, forKey: .event)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(bytes, forKey: .bytes)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(roomEvent, forKey: .roomEvent)
    }
}

public enum DaemonStreamEventName {
    public static let output = "output"
    public static let exit = "exit"
    public static let exited = "exited"
    public static let replay = "replay"
    public static let replayEnd = "replayEnd"
    public static let roomEvent = "room-event"
}

public struct DaemonResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var result: JSONValue?
    public var error: String?
    public var generation: UInt64

    public init(
        ok: Bool,
        result: JSONValue? = nil,
        error: String? = nil,
        generation: UInt64
    ) {
        self.ok = ok
        self.result = result
        self.error = error
        self.generation = generation
    }

    public static func success(_ result: JSONValue, generation: UInt64) -> DaemonResponse {
        DaemonResponse(ok: true, result: result, generation: generation)
    }

    public static func failure(_ message: String, generation: UInt64) -> DaemonResponse {
        DaemonResponse(ok: false, error: message, generation: generation)
    }
}

public enum DaemonDefaults {
    public static let idleSeconds: TimeInterval = 60
    public static let ringLines = 10_000
    public static let ringByteCapacity = 512 * 1024
    public static let ringBytes = ringByteCapacity
    public static let closeGraceSeconds: TimeInterval = 5
    public static let socketFileMode: UInt16 = 0o600
    public static let socketDirectoryMode: UInt16 = 0o700
}
