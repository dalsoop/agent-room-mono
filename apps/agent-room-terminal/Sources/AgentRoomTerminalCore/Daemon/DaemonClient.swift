import Darwin
import Foundation

public struct DaemonClient: Sendable {
    public var socketURL: URL
    public var daemonExecutable: URL?
    public var spawnIfMissing: Bool
    public var connectAttempts: Int
    public var connectRetryNanos: UInt64
    public var authority: String?
    public var roomSession: String?

    public init(
        socketURL: URL,
        daemonExecutable: URL? = nil,
        spawnIfMissing: Bool = true,
        connectAttempts: Int = 40,
        connectRetryNanos: UInt64 = 50_000_000,
        authority: String? = nil,
        roomSession: String? = nil
    ) {
        self.socketURL = socketURL
        self.daemonExecutable = daemonExecutable
        self.spawnIfMissing = spawnIfMissing
        self.connectAttempts = connectAttempts
        self.connectRetryNanos = connectRetryNanos
        self.authority = authority
        self.roomSession = roomSession
    }

    public func send(_ request: DaemonRequest) throws -> DaemonResponse {
        let fd = try connectOrSpawn()
        defer { Darwin.close(fd) }
        let frame = try DaemonFraming.encode(stamped(request))
        try UnixSocketIO.writeAll(fd: fd, data: frame)
        let payload = try UnixSocketIO.readFrame(fd: fd)
        return try DaemonFraming.decodeResponse(payload)
    }

    /// Holds the connection open and delivers attach/output/exit frames until exit or disconnect.
    public func attach(
        sessionID: String,
        lines: Int = 100,
        replayBytes: Int? = nil,
        onFrame: (DaemonStreamFrame) throws -> Void
    ) throws {
        let fd = try connectOrSpawn()
        defer { Darwin.close(fd) }
        let request = stamped(
            DaemonRequest(op: .attach, sessionID: sessionID, lines: lines, replayBytes: replayBytes)
        )
        try UnixSocketIO.writeAll(fd: fd, data: try DaemonFraming.encode(request))
        var decoder = DaemonFrameDecoder()
        while true {
            let chunk = try UnixSocketIO.readSome(fd: fd)
            let payloads = try decoder.append(chunk)
            for payload in payloads {
                let frame = try JSONDecoder().decode(DaemonStreamFrame.self, from: payload)
                try onFrame(frame)
                if case .some(false) = frame.ok {
                    throw DaemonProtocolError.requestFailed(frame.error ?? "attach failed")
                }
                if frame.event == DaemonStreamEventName.exit || frame.event == DaemonStreamEventName.exited {
                    return
                }
            }
        }
    }

    /// 원시 바이트 스트림 attach: replayBytes 만큼 꼬리를 먼저 받고 replayEnd 이벤트를 거쳐 실시간 바이트를 수신한다.
    public func attachRaw(
        sessionID: String,
        replayBytes: Int = DaemonDefaults.ringByteCapacity,
        onBytes: (Data) throws -> Void,
        onReplayEnd: (() throws -> Void)? = nil
    ) throws {
        let fd = try connectOrSpawn()
        defer { Darwin.close(fd) }
        let request = stamped(
            DaemonRequest(op: .attach, sessionID: sessionID, replayBytes: replayBytes)
        )
        try UnixSocketIO.writeAll(fd: fd, data: try DaemonFraming.encode(request))
        var decoder = DaemonFrameDecoder()
        while true {
            let chunk = try UnixSocketIO.readSome(fd: fd)
            let payloads = try decoder.append(chunk)
            for payload in payloads {
                let frame = try JSONDecoder().decode(DaemonStreamFrame.self, from: payload)
                if case .some(false) = frame.ok {
                    throw DaemonProtocolError.requestFailed(frame.error ?? "attach failed")
                }
                if let data = frame.outputBytes, !data.isEmpty {
                    try onBytes(data)
                }
                if frame.event == DaemonStreamEventName.replayEnd {
                    try onReplayEnd?()
                }
                if frame.event == DaemonStreamEventName.exit || frame.event == DaemonStreamEventName.exited {
                    return
                }
            }
        }
    }

    /// room.events 스트림을 수신한다.
    public func subscribeEvents(
        roomDir: String,
        since: Int = 0,
        onEvent: (RoomEvent) throws -> Void
    ) throws {
        let fd = try connectOrSpawn()
        defer { Darwin.close(fd) }
        let request = stamped(
            DaemonRequest.events(roomDir: roomDir, since: since)
        )
        try UnixSocketIO.writeAll(fd: fd, data: try DaemonFraming.encode(request))
        var decoder = DaemonFrameDecoder()
        while true {
            let chunk = try UnixSocketIO.readSome(fd: fd)
            let payloads = try decoder.append(chunk)
            for payload in payloads {
                let frame = try JSONDecoder().decode(DaemonStreamFrame.self, from: payload)
                if case .some(false) = frame.ok {
                    throw DaemonProtocolError.requestFailed(frame.error ?? "events failed")
                }
                if let event = frame.roomEvent {
                    try onEvent(event)
                }
            }
        }
    }

    public func resize(sessionID: String, columns: Int, rows: Int) throws {
        let response = try send(.resize(sessionID: sessionID, columns: columns, rows: rows))
        if !response.ok {
            throw DaemonProtocolError.requestFailed(response.error ?? "resize failed")
        }
    }

    public func sendInput(sessionID: String, bytes: Data) throws {
        let response = try send(.sendInput(sessionID: sessionID, bytes: bytes))
        if !response.ok {
            throw DaemonProtocolError.requestFailed(response.error ?? "input failed")
        }
    }

    private func stamped(_ request: DaemonRequest) -> DaemonRequest {
        var copy = request
        if copy.authority == nil {
            copy.authority = authority
        }
        if copy.roomSession == nil {
            copy.roomSession = roomSession
        }
        return copy
    }

    public func connectOrSpawn() throws -> Int32 {
        if let fd = tryConnect() {
            return fd
        }
        if spawnIfMissing {
            try spawnDaemon()
        }
        var lastError: Error = UnixSocketIOError.closed
        for _ in 0..<connectAttempts {
            if let fd = tryConnect() {
                return fd
            }
            lastError = UnixSocketIOError.systemCall("connect", errno)
            nanosleepRetry()
        }
        throw lastError
    }

    private func tryConnect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        do {
            try UnixSocketIO.configureNoSIGPIPE(fd)
            var address = try UnixSocketIO.socketAddress(path: socketURL.path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                    Darwin.connect(fd, sock, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result == 0 {
                return fd
            }
            Darwin.close(fd)
            return nil
        } catch {
            Darwin.close(fd)
            return nil
        }
    }

    private func spawnDaemon() throws {
        guard let executable = DaemonExecutable.locate(override: daemonExecutable) else {
            throw UnixSocketIOError.systemCall("spawn-missing-binary", ENOENT)
        }
        let generation = socketURL.deletingLastPathComponent()
            .appendingPathComponent(AppPaths.daemonGenerationFileName)
        try DaemonSpawner.spawn(
            executable: executable,
            arguments: [
                "--socket", socketURL.path,
                "--generation", generation.path,
            ]
        )
    }

    private func nanosleepRetry() {
        var spec = timespec(
            tv_sec: 0,
            tv_nsec: Int(clamping: connectRetryNanos)
        )
        nanosleep(&spec, nil)
    }
}

enum DaemonSpawner {
    static func spawn(executable: URL, arguments: [String]) throws {
        var pid: pid_t = 0
        let argvStrings = [executable.path] + arguments
        var cArgs = argvStrings.map { strdup($0) }
        cArgs.append(nil)
        defer {
            for pointer in cArgs {
                free(pointer)
            }
        }
        let status = cArgs.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(
                &pid,
                executable.path,
                nil,
                nil,
                buffer.baseAddress,
                environ
            )
        }
        guard status == 0 else {
            throw UnixSocketIOError.systemCall("posix_spawn", status)
        }
    }
}
