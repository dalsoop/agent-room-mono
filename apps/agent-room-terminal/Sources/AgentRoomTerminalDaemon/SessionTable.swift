import Darwin
import Foundation
import AgentRoomTerminalCore

struct PersistedSessionRecord: Codable, Equatable, Sendable {
    var sessionID: String
    var roomDir: String
    var pgid: Int32
    var shell: String
    var startedAt: String
    /// `predecessor` | `successor`. 옛 파일은 키가 없고 전임으로 본다.
    var sessionRole: String

    enum CodingKeys: String, CodingKey {
        case sessionID, roomDir, pgid, shell, startedAt, sessionRole
    }

    init(
        sessionID: String,
        roomDir: String,
        pgid: Int32,
        shell: String,
        startedAt: String,
        sessionRole: String = RoomSessionRole.predecessor.rawValue
    ) {
        self.sessionID = sessionID
        self.roomDir = roomDir
        self.pgid = pgid
        self.shell = shell
        self.startedAt = startedAt
        self.sessionRole = sessionRole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        roomDir = try container.decode(String.self, forKey: .roomDir)
        pgid = try container.decode(Int32.self, forKey: .pgid)
        shell = try container.decode(String.self, forKey: .shell)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        sessionRole = try container.decodeIfPresent(String.self, forKey: .sessionRole)
            ?? RoomSessionRole.predecessor.rawValue
    }

    var startedAtDate: Date {
        PersistedSessionRecord.parseDate(startedAt) ?? Date(timeIntervalSince1970: 0)
    }

    static func formatDate(_ date: Date) -> String {
        makeFormatter().string(from: date)
    }

    static func parseDate(_ text: String) -> Date? {
        makeFormatter().date(from: text)
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

struct PersistedSessionFile: Codable, Equatable, Sendable {
    var sessions: [PersistedSessionRecord]
}

final class SessionTable {
    static let fileName = "sessions.json"

    private let lock = NSLock()
    private var sessions: [String: PtyTerminalSession] = [:]
    private let fileURL: URL
    private let ringLines: Int
    private let ringByteCapacity: Int

    init(
        fileURL: URL,
        ringLines: Int = DaemonDefaults.ringLines,
        ringByteCapacity: Int = DaemonDefaults.ringByteCapacity
    ) {
        self.fileURL = fileURL
        self.ringLines = ringLines
        self.ringByteCapacity = ringByteCapacity
    }

    /// `~/.tenants/_daemon/sessions.json` — AppPaths 의 데몬 디렉터리.
    static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        AppPaths.daemonLogURL(environment: environment)
            .deletingLastPathComponent()
            .appendingPathComponent(fileName, isDirectory: false)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.count
    }

    var isEmpty: Bool { count == 0 }

    func add(_ session: PtyTerminalSession) {
        lock.lock()
        sessions[session.sessionID] = session
        persistLocked()
        lock.unlock()
    }

    func get(_ sessionID: String) -> PtyTerminalSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[sessionID]
    }

    func remove(_ sessionID: String) -> PtyTerminalSession? {
        lock.lock()
        defer { lock.unlock() }
        let removed = sessions.removeValue(forKey: sessionID)
        persistLocked()
        return removed
    }

    func all() -> [PtyTerminalSession] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values)
    }

    func infos() -> [TerminalSessionInfo] {
        all().map(\.info)
    }

    /// 한 방에 전임·후임 세션이 같이 있을 수 있다. roomDir 로 묶는다.
    func sessions(inRoom roomDir: String) -> [PtyTerminalSession] {
        let want = SessionAuthorizer.standardized(roomDir)
        return all().filter { SessionAuthorizer.standardized($0.roomDir) == want }
    }

    func persist() throws {
        lock.lock()
        defer { lock.unlock() }
        try writeLocked()
    }

    /// 디스크의 표를 읽어 pgid 가 살아 있으면 복구, 죽어 있으면 `state/term.log` 에
    /// `recovered-dead` 를 남기고 버린다.
    func restore() throws {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeAll()
        let records = try loadRecords()
        var kept: [PersistedSessionRecord] = []
        var deadRooms: [String] = []
        for record in records {
            if ProcessGroupProbe.isAlive(pgid: record.pgid) {
                let session = PtyTerminalSession.recovered(
                    from: record,
                    ringLines: ringLines,
                    ringByteCapacity: ringByteCapacity
                )
                sessions[session.sessionID] = session
                kept.append(record)
            } else {
                appendRecoveredDead(roomDir: record.roomDir)
                deadRooms.append(record.roomDir)
            }
        }
        let liveRooms = Set(kept.map { SessionAuthorizer.standardized($0.roomDir) })
        for roomDir in deadRooms {
            if !liveRooms.contains(SessionAuthorizer.standardized(roomDir)) {
                unseedDeadRoom(roomDir: roomDir)
            }
        }
        try writeRecords(kept)
    }

    private func persistLocked() {
        do {
            try writeLocked()
        } catch {
            fputs("session-table persist failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func writeLocked() throws {
        let records = sessions.values.map { session in
            PersistedSessionRecord(
                sessionID: session.sessionID,
                roomDir: session.roomDir,
                pgid: session.pgid,
                shell: session.shell,
                startedAt: PersistedSessionRecord.formatDate(session.startedAt),
                sessionRole: session.sessionRole
            )
        }
        try writeRecords(records)
    }

    private func writeRecords(_ records: [PersistedSessionRecord]) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(PersistedSessionFile(sessions: records))
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadRecords() throws -> [PersistedSessionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(PersistedSessionFile.self, from: data).sessions
        } catch {
            return try decoder.decode([PersistedSessionRecord].self, from: data)
        }
    }

    private func appendRecoveredDead(roomDir: String) {
        let url = URL(fileURLWithPath: roomDir)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("term.log", isDirectory: false)
        do {
            try LineRingBuffer.spill("recovered-dead", to: url)
        } catch {
            fputs("recovered-dead log failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private func unseedDeadRoom(roomDir: String) {
        let roomURL = URL(fileURLWithPath: roomDir, isDirectory: true)
        for tool in AgentRoomTool.allCases {
            _ = AgentCredentialInjector.unseed(tool: tool, roomURL: roomURL)
        }
    }
}

enum ProcessGroupProbe {
    /// 리더가 먼저 죽어도 그룹에 자식이 남아 있으면 살아 있다고 본다.
    /// `kill(-pgid)` 만 쓰면 그룹 리더가 아닌 pid(테스트의 Foundation.Process)를 놓친다.
    static func isAlive(pgid: pid_t) -> Bool {
        if pgid <= 0 { return false }
        if signalZero(-pgid) { return true }
        return signalZero(pgid)
    }

    private static func signalZero(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
