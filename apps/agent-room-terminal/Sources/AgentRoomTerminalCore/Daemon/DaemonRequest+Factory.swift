import Foundation

extension DaemonRequest {
    public static func openSession(
        roomDir: String,
        envFile: String,
        shell: String,
        seatbeltProfile: String? = nil,
        sessionRole: String? = nil,
        columns: Int? = nil,
        rows: Int? = nil,
        banner: String? = nil
    ) -> DaemonRequest {
        var req = DaemonRequest(
            op: .openSession,
            roomDir: roomDir,
            envFile: envFile,
            shell: shell,
            seatbeltProfile: seatbeltProfile,
            sessionRole: sessionRole
        )
        if columns != nil || rows != nil {
            req.windowDimensions = TerminalDimensions(columns: columns, rows: rows)
        }
        req.banner = banner
        return req
    }

    public static func closeSession(sessionID: String) -> DaemonRequest {
        DaemonRequest(op: .closeSession, sessionID: sessionID)
    }

    public static func exec(
        sessionID: String?,
        roomDir: String,
        argv: [String],
        timeoutSeconds: Int? = nil,
        launch: Bool? = nil,
        raw: Bool? = nil,
        tool: String? = nil
    ) -> DaemonRequest {
        var req = DaemonRequest(
            op: .exec,
            roomDir: roomDir,
            sessionID: sessionID,
            argv: argv,
            timeoutSeconds: timeoutSeconds,
            launch: launch
        )
        req.raw = raw
        req.tool = tool
        return req
    }

    public static func snapshot(sessionID: String, lines: Int) -> DaemonRequest {
        DaemonRequest(op: .snapshot, sessionID: sessionID, lines: lines)
    }

    public static func listSessions() -> DaemonRequest {
        DaemonRequest(op: .listSessions)
    }

    public static func input(sessionID: String, text: String) -> DaemonRequest {
        DaemonRequest(op: .input, sessionID: sessionID, input: text)
    }

    public static func attach(
        sessionID: String,
        lines: Int = 100,
        replayBytes: Int? = nil
    ) -> DaemonRequest {
        DaemonRequest(op: .attach, sessionID: sessionID, lines: lines, replayBytes: replayBytes)
    }

    public static func resize(
        sessionID: String,
        columns: Int,
        rows: Int
    ) -> DaemonRequest {
        DaemonRequest(op: .resize, sessionID: sessionID, columns: columns, rows: rows)
    }

    public static func sendInput(sessionID: String, bytes: Data) -> DaemonRequest {
        DaemonRequest(op: .input, sessionID: sessionID, bytes: bytes.base64EncodedString())
    }

    public static func ensureNetworkProxy(
        roomDir: String,
        allowedDomains: [String]
    ) -> DaemonRequest {
        DaemonRequest(
            op: .ensureNetworkProxy,
            roomDir: roomDir,
            allowedDomains: allowedDomains
        )
    }

    public static func events(
        roomDir: String,
        since: Int = 0
    ) -> DaemonRequest {
        var req = DaemonRequest(op: .events, roomDir: roomDir)
        req.since = since
        return req
    }
}
