import Darwin
import Foundation
; import SwiftTerm
import AgentRoomTerminalCore

/// PTY 세션의 샌드박스 설정. seatbelt 프로필과 srt 설정 경로를 하나로 묶는다.
struct PtySandboxConfig: Sendable {
    var seatbeltProfile: String?
    var srtSettingsPath: String?

    static let none = PtySandboxConfig()
}

final class PtyTerminalSession {
    let sessionID: String
    let roomDir: String
    let sessionRole: String
    let sandboxConfig: PtySandboxConfig
    private(set) var env: [String: String]
    /// 세션 셸이 `zsh -r` 이면 true — exec 도 같은 선에서 막는다(`ExecPolicy`).
    private(set) var restrictedShell = true
    private(set) var shell: String
    private(set) var startedAt: Date
    /// 데몬 재기동 후 pgid 만 복구한 세션. PTY 가 없어 attach 불가.
    private(set) var recovered: Bool

    private let ringLines: Int
    private let queue: DispatchQueue
    private var process: LocalProcess?
    private var byteRing: ByteRingBuffer
    private var windowSize: winsize
    private let sizeLock = NSLock()
    private var pgidValue: pid_t = 0
    private var subscribers: [UUID: SessionSubscriber] = [:]
    private var outputVersion: UInt64 = 0
    private var snapshotCache = SnapshotCache()
    private var exitState = ExitState()

    init(
        sessionID: String,
        roomDir: String,
        env: [String: String],
        sandbox: PtySandboxConfig = .none,
        ringLines: Int,
        ringByteCapacity: Int = DaemonDefaults.ringByteCapacity,
        sessionRole: String = RoomSessionRole.predecessor.rawValue,
        dimensions: TerminalDimensions? = nil
    ) {
        self.sessionID = sessionID
        self.roomDir = roomDir
        self.sessionRole = sessionRole
        self.env = env
        self.sandboxConfig = sandbox
        self.ringLines = max(1, ringLines)
        self.shell = "zsh -r"
        self.startedAt = Date()
        self.recovered = false
        self.queue = DispatchQueue(label: "agent-room-terminal.pty.\(sessionID)")
        self.byteRing = ByteRingBuffer(capacity: ringByteCapacity)
        let cols = UInt16(clamping: dimensions?.columns ?? 80)
        let r = UInt16(clamping: dimensions?.rows ?? 24)
        self.windowSize = winsize(ws_row: r, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        self.pgidValue = 0
        self.restrictedShell = true
        let local = LocalProcess(delegate: self, dispatchQueue: queue)
        self.process = local
    }

    init(
        recovered record: PersistedSessionRecord,
        ringLines: Int,
        ringByteCapacity: Int = DaemonDefaults.ringByteCapacity
    ) {
        self.sessionID = record.sessionID
        self.roomDir = record.roomDir
        self.sessionRole = record.sessionRole
        self.env = [:]
        self.sandboxConfig = .none
        self.ringLines = max(1, ringLines)
        self.shell = record.shell
        self.startedAt = record.startedAtDate
        self.recovered = true
        self.queue = DispatchQueue(label: "agent-room-terminal.pty.\(record.sessionID)")
        self.byteRing = ByteRingBuffer(capacity: ringByteCapacity)
        self.windowSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        self.pgidValue = record.pgid
        self.restrictedShell = ExecPolicy.isRestricted(shell: record.shell)
        self.process = nil
    }

    static func recovered(
        from record: PersistedSessionRecord,
        ringLines: Int,
        ringByteCapacity: Int = DaemonDefaults.ringByteCapacity
    ) -> PtyTerminalSession {
        PtyTerminalSession(recovered: record, ringLines: ringLines, ringByteCapacity: ringByteCapacity)
    }

    static func execSession(
        sessionID: String,
        roomDir: String,
        ringLines: Int = DaemonDefaults.ringLines,
        ringByteCapacity: Int = DaemonDefaults.ringByteCapacity
    ) -> PtyTerminalSession {
        let record = PersistedSessionRecord(
            sessionID: sessionID,
            roomDir: roomDir,
            pgid: 0,
            shell: "exec",
            startedAt: PersistedSessionRecord.formatDate(Date()),
            sessionRole: "exec"
        )
        return PtyTerminalSession(recovered: record, ringLines: ringLines, ringByteCapacity: ringByteCapacity)
    }

    var info: TerminalSessionInfo {
        TerminalSessionInfo(
            sessionID: sessionID,
            roomDir: roomDir,
            pgid: pgidValue,
            sessionRole: sessionRole
        )
    }

    var pgid: pid_t {
        queue.sync { pgidValue }
    }

    func start(shell: String, banner: String? = nil) throws {
        if recovered {
            throw UnixSocketIOError.systemCall("pty-start-recovered", 1)
        }
        if let banner, !banner.isEmpty {
            let normalized = banner.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n")
            let bannerText = normalized.hasSuffix("\r\n") ? normalized : (normalized + "\r\n")
            if let data = bannerText.data(using: .utf8) {
                byteRing.append(slice: Array(data)[...])
                outputVersion &+= 1
            }
        }
        self.shell = shell
        restrictedShell = ExecPolicy.isRestricted(shell: shell)
        var merged = env
        merged["ROOM_SESSION"] = sessionID
        if merged["TERM"] == nil {
            merged["TERM"] = "xterm-256color"
        }
        env = merged
        let launch: (executable: String, arguments: [String])
        if let srtPath = sandboxConfig.srtSettingsPath,
           let srtCmd = SRTLaunch.command(shell: shell, settingsPath: srtPath) {
            launch = srtCmd
        } else {
            launch = try SeatbeltLaunch.command(shell: shell, profile: sandboxConfig.seatbeltProfile)
        }
        guard let process else {
            throw UnixSocketIOError.systemCall("pty-start", 1)
        }
        process.startProcess(
            executable: launch.executable,
            args: launch.arguments,
            environment: EnvFile.pairs(merged),
            currentDirectory: roomDir
        )
        waitForPid()
        if pgidValue <= 0 {
            throw UnixSocketIOError.systemCall("pty-start", 1)
        }
    }

    func injectOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.sync {
            byteRing.append(data)
            outputVersion &+= 1
            let outputs = subscribers.values.map(\.onOutput)
            for onOutput in outputs {
                onOutput(data)
            }
        }
    }

    func send(_ text: String) {
        send(Data(text.utf8))
    }

    func send(_ data: Data) {
        if recovered { return }
        process?.send(data: Array(data)[...])
    }

    var hasExited: Bool {
        queue.sync { exitState.didExit }
    }

    var recordedExitCode: Int32 {
        queue.sync { exitState.code }
    }

    func subscribe(
        replayBytes: Int? = nil,
        onReplay: ((Data) -> Void)? = nil,
        onReplayEnd: (() -> Void)? = nil,
        onOutput: @escaping (Data) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> UUID {
        let id = UUID()
        var pendingExit: Int32?
        queue.sync {
            if let replayBytes {
                if replayBytes > 0 {
                    let tail = byteRing.tail(replayBytes)
                    if !tail.isEmpty {
                        onReplay?(tail)
                    }
                }
                onReplayEnd?()
            }
            subscribers[id] = SessionSubscriber(onOutput: onOutput, onExit: onExit)
            if exitState.didExit {
                pendingExit = exitState.code
            }
        }
        if let code = pendingExit {
            onExit(code)
        }
        return id
    }

    func subscribe(onOutput: @escaping (Data) -> Void, onExit: @escaping (Int32) -> Void) -> UUID {
        subscribe(replayBytes: nil, onReplay: nil, onReplayEnd: nil, onOutput: onOutput, onExit: onExit)
    }

    func unsubscribe(_ id: UUID) {
        queue.sync { () -> Void in
            subscribers.removeValue(forKey: id)
        }
    }

    func snapshot(lines: Int) -> [String] {
        queue.sync {
            if outputVersion == snapshotCache.version && lines == snapshotCache.lines && !snapshotCache.cached.isEmpty {
                return snapshotCache.cached
            }
            let result = parseSnapshotLines(count: lines)
            snapshotCache = SnapshotCache(version: outputVersion, lines: lines, cached: result)
            return result
        }
    }

    private func parseSnapshotLines(count: Int) -> [String] {
        let bytes = byteRing.tail(byteRing.capacity)
        guard !bytes.isEmpty else { return [] }
        let size = currentWindowSize
        let cols = max(1, Int(size.ws_col))
        let targetRows = max(max(1, Int(size.ws_row)), max(count, ringLines))
        let delegate = HeadlessTerminalDelegate()
        let term = Terminal(
            delegate: delegate,
            options: TerminalOptions(cols: cols, rows: targetRows, scrollback: 0)
        )
        term.feed(byteArray: Array(bytes))
        var lines: [String] = []
        for r in 0..<term.rows {
            guard let line = term.getLine(row: r) else { continue }
            lines.append(line.translateToString(trimRight: true, skipNullCellsFollowingWide: true))
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        let requested = max(0, count)
        if requested >= lines.count {
            return lines
        }
        return Array(lines.suffix(requested))
    }

    func byteTail(_ count: Int) -> Data {
        queue.sync { byteRing.tail(count) }
    }

    func updateByteRingCapacity(_ capacity: Int) {
        queue.sync { byteRing.setCapacity(capacity) }
    }

    var currentWindowSize: winsize {
        sizeLock.lock()
        defer { sizeLock.unlock() }
        return windowSize
    }

    var childFileDescriptor: Int32? {
        process?.childfd
    }

    var terminalSize: (cols: Int, rows: Int)? {
        let size = currentWindowSize
        return (Int(size.ws_col), Int(size.ws_row))
    }

    func resize(columns: Int, rows: Int) {
        queue.sync {
            let cols = UInt16(clamping: columns)
            let r = UInt16(clamping: rows)
            let size = winsize(ws_row: r, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
            sizeLock.lock()
            windowSize = size
            sizeLock.unlock()

            if let fd = process?.childfd, fd >= 0 {
                var copy = size
                _ = Darwin.ioctl(fd, TIOCSWINSZ, &copy)
            }
            outputVersion &+= 1
        }
    }

    func close(grace: TimeInterval) {
        let pid = livePid()
        if pid > 0 {
            killpg(pid, SIGTERM)
            process?.terminate()
        }
        waitUntilStopped(grace: grace)
        let still = livePid()
        if still > 0 && ProcessGroupProbe.isAlive(pgid: still) {
            killpg(still, SIGKILL)
            queue.sync {
                notifyExit(128 + SIGKILL)
            }
            return
        }
        queue.sync {
            notifyExit(exitState.code)
        }
    }

    static func normalizeExitCode(_ status: Int32) -> Int32 {
        if (status & 0x7f) == 0 {
            return (status >> 8) & 0xff
        } else {
            return 128 + (status & 0x7f)
        }
    }



    private func waitForPid() {
        for _ in 0..<50 {
            if (process?.shellPid ?? 0) > 0 { break }
            var wait = timespec(tv_sec: 0, tv_nsec: 10_000_000)
            nanosleep(&wait, nil)
        }
        let pid = process?.shellPid ?? 0
        pgidValue = pid
        if pid > 0 {
            _ = setpgid(pid, pid)
        }
    }

    private func livePid() -> pid_t {
        let current = process?.shellPid ?? 0
        if current > 0 { return current }
        return pgidValue
    }

    private func waitUntilStopped(grace: TimeInterval) {
        let deadline = Date().addingTimeInterval(grace)
        while (process?.running ?? false) && Date() < deadline {
            var wait = timespec(tv_sec: 0, tv_nsec: 50_000_000)
            nanosleep(&wait, nil)
        }
    }

    private func notifyExit(_ code: Int32) {
        guard !exitState.didExit else { return }
        exitState.didExit = true
        exitState.code = code
        pgidValue = 0
        let exits = subscribers.values.map(\.onExit)
        subscribers.removeAll()
        for onExit in exits {
            onExit(code)
        }
        unseedRoomCredentials()
    }

    var isExited: Bool { exitState.didExit }
    var canUnseedCredentials: (() -> Bool)? {
        get { exitState.canUnseedCredentials }
        set { exitState.canUnseedCredentials = newValue }
    }

    private func unseedRoomCredentials() {
        if let canUnseed = canUnseedCredentials, !canUnseed() {
            return
        }
        let roomURL = URL(fileURLWithPath: roomDir, isDirectory: true)
        for tool in AgentRoomTool.allCases {
            _ = AgentCredentialInjector.unseed(tool: tool, roomURL: roomURL)
        }
    }
}

extension PtyTerminalSession: LocalProcessDelegate {
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        let code = exitCode.map(Self.normalizeExitCode) ?? 0
        notifyExit(code)
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        let data = Data(slice)
        byteRing.append(slice: slice)
        outputVersion &+= 1
        let outputs = subscribers.values.map(\.onOutput)
        for onOutput in outputs {
            onOutput(data)
        }
    }

    func getWindowSize() -> winsize {
        currentWindowSize
    }
}

private struct SessionSubscriber {
    let onOutput: (Data) -> Void
    let onExit: (Int32) -> Void
}

private struct SnapshotCache {
    var version: UInt64 = 0
    var lines: Int = 0
    var cached: [String] = []
}

private struct ExitState {
    var didExit: Bool = false
    var code: Int32 = 0
    var canUnseedCredentials: (() -> Bool)? = nil
}

private final class HeadlessTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func getWindowSize() -> winsize {
        winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
    }
}
