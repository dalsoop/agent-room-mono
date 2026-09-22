import Darwin
import Foundation
import CommandKit
import AgentRoomTerminalCore

enum DaemonCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        _ = CLIArgs.takeJSON(&rest)
        let sub = rest.first ?? "status"
        switch sub {
        case "start":
            CLIAsync.run { CLIIO.printOKObject(try await start()) }
        case "stop":
            CLIAsync.run { CLIIO.printOKObject(try await stop()) }
        case "status":
            CLIIO.printOKObject(status())
        case "sessions":
            CLIAsync.run { CLIIO.printOKObject(try await sessions()) }
        default:
            CLIIO.fail("usage: daemon start|stop|status|sessions [--json]", code: CLIExit.usage)
        }
    }

    static func start() async throws -> [String: Any] {
        if isReachable() {
            return status()
        }
        guard let executable = DaemonExecutable.locate() else {
            throw DaemonCLIError.binaryMissing
        }
        try spawn(executable: executable)
        if !(try await waitUntilReachable()) {
            throw DaemonCLIError.startFailed
        }
        return status()
    }

    /// generation 파일의 수정 시각 — 데몬이 마지막으로 올라온 시각의 근사값. 없으면 nil.
    private static func generationFileModificationDate() -> Date? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: AppPaths.daemonGenerationURL().path)
            return attrs[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    static func stop() async throws -> [String: Any] {
        var pid = peerPID()
        if pid == nil {
            let socketPath = AppPaths.daemonSocketURL().path
            let pgrep = CommandKitSync.run(
                "/usr/bin/pgrep",
                ["-f", "agent-room-terminal-daemon.*--socket \(socketPath)"],
                timeout: 3
            )
            if pgrep.exitCode == 0,
               let first = pgrep.stdout.split(separator: "\n").first,
               let p = pid_t(first.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) {
                pid = p
            }
        }
        guard let targetPID = pid, targetPID > 1 else {
            return ["stopped": true, "forced": false, "pid": 0]
        }
        kill(targetPID, SIGTERM)
        let gone = try await waitUntilProcessExited(pid: targetPID, attempts: 40)
        var forced = false
        if !gone {
            kill(targetPID, SIGKILL)
            forced = true
            _ = try await waitUntilProcessExited(pid: targetPID, attempts: 20)
        }
        return ["stopped": true, "forced": forced, "pid": Int(targetPID)]
    }

    static func status() -> [String: Any] {
        let generation = currentGeneration()
        let pid = peerPID()
        var result: [String: Any] = [
            "running": pid != nil,
            "generation": generation,
            "socket": AppPaths.daemonSocketURL().path,
        ]
        if let pid {
            result["pid"] = Int(pid)
            if let binary = DaemonExecutable.locate() {
                result["binaryPath"] = binary.path
            }
            if let date = generationFileModificationDate() {
                result["startedAt"] = ISO8601DateFormatter().string(from: date)
            }
        }
        return result
    }

    static func currentGeneration() -> UInt64 {
        do {
            return try GenerationStore(url: AppPaths.daemonGenerationURL()).readCurrent()
        } catch {
            return 0
        }
    }

    static func isReachable() -> Bool {
        peerPID() != nil
    }

    static func commandRoomClient() -> DaemonClient {
        DaemonClient(
            socketURL: AppPaths.daemonSocketURL(),
            spawnIfMissing: false,
            connectAttempts: 8,
            authority: SessionAuthorizer.commandRoomAuthority
        )
    }

    static func probeClient() -> DaemonClient {
        DaemonClient(
            socketURL: AppPaths.daemonSocketURL(),
            spawnIfMissing: false,
            connectAttempts: 1,
            connectRetryNanos: 0
        )
    }

    private static func spawn(executable: URL) throws {
        let logURL = AppPaths.daemonLogURL()
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var pid: pid_t = 0
        let argvStrings = [
            executable.path,
            "--socket", AppPaths.daemonSocketURL().path,
            "--generation", AppPaths.daemonGenerationURL().path,
        ]
        var cArgs = argvStrings.map { strdup($0) }
        cArgs.append(nil)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        let flags = O_WRONLY | O_CREAT | O_APPEND
        posix_spawn_file_actions_addopen(&actions, 1, logURL.path, flags, 0o644)
        posix_spawn_file_actions_addopen(&actions, 2, logURL.path, flags, 0o644)
        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attrs, 0)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attrs)
            for pointer in cArgs { free(pointer) }
        }
        let status = cArgs.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(&pid, executable.path, &actions, &attrs, buffer.baseAddress, environ)
        }
        guard status == 0 else {
            throw DaemonCLIError.spawnFailed(status)
        }
    }

    private static func waitUntilReachable() async throws -> Bool {
        for _ in 0..<40 {
            if isReachable() { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    @discardableResult
    private static func waitUntilProcessExited(pid: pid_t, attempts: Int = 40) async throws -> Bool {
        for _ in 0..<attempts {
            if kill(pid, 0) != 0 { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    @discardableResult
    private static func waitUntilGone(attempts: Int = 40) async throws -> Bool {
        for _ in 0..<attempts {
            if !isReachable() { return true }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    private static func peerPID() -> pid_t? {
        let fd: Int32
        do {
            fd = try probeClient().connectOrSpawn()
        } catch {
            return nil
        }
        defer { Darwin.close(fd) }
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        let result = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length)
        guard result == 0, pid > 1 else { return nil }
        return pid
    }

    /// 데몬에 세션 목록을 요청하여 방별 `{roomID, sessionID, state}` 를 반환한다.
    static func sessions() async throws -> Any {
        let client = commandRoomClient()
        let request = DaemonRequest(op: .listSessions)
        let response = try client.send(request)
        guard response.ok, let result = response.result else {
            throw DaemonCLIError.startFailed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum DaemonCLIError: Error, LocalizedError {
    case binaryMissing
    case startFailed
    case spawnFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "agent-room-terminal-daemon not next to this CLI"
        case .startFailed:
            return "daemon did not accept connections"
        case .spawnFailed(let code):
            return "posix_spawn failed: \(code)"
        }
    }
}
