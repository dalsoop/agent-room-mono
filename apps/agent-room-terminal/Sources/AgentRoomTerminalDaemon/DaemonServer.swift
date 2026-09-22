import Darwin
import Dispatch
import Foundation
import AgentRoomTerminalCore

/// 데몬 튜닝값 묶음 — 유휴 종료 시간과 링 버퍼 크기.
struct DaemonTuning {
    var idleSeconds: TimeInterval
    var ringLines: Int
    var ringByteCapacity: Int

    init(
        idleSeconds: TimeInterval = DaemonDefaults.idleSeconds,
        ringLines: Int = DaemonDefaults.ringLines,
        ringByteCapacity: Int = DaemonDefaults.ringByteCapacity
    ) {
        self.idleSeconds = idleSeconds
        self.ringLines = ringLines
        self.ringByteCapacity = ringByteCapacity
    }
}

final class DaemonServer: @unchecked Sendable {
    let socketURL: URL
    let logURL: URL
    private let generationStore: GenerationStore
    private let clock: DaemonClock
    private let listener: DaemonListener
    private let sessions: SessionTable
    let proxies = RoomProxyTable()
    let eventHub = RoomEventHub()
    private let lock = NSLock()
    private let stopSemaphore = DispatchSemaphore(value: 0)
    private let serveQueue = DispatchQueue(
        label: "agent-room-terminal.daemon.serve",
        attributes: .concurrent
    )
    private var acceptSource: DispatchSourceRead?
    private var idleSource: DispatchSourceTimer?
    private var lastEmptyAt: Date?
    private var stopped = false
    private var consecutiveAcceptFailures = 0
    static let acceptFailureCircuitBreaker = 100

    private(set) var generation: UInt64 = 0
    var tuning: DaemonTuning
    let launchBackend: RoomAgentLaunching

    init(
        socketURL: URL,
        generationURL: URL,
        clock: DaemonClock = SystemDaemonClock(),
        tuning: DaemonTuning = DaemonTuning(),
        logURL: URL? = nil,
        sessionsURL: URL? = nil,
        launchBackend: RoomAgentLaunching = LaunchBackendFactory.resolve()
    ) {
        self.socketURL = socketURL
        self.generationStore = GenerationStore(url: generationURL)
        self.clock = clock
        self.listener = DaemonListener(socketURL: socketURL)
        self.tuning = tuning
        self.launchBackend = launchBackend
        self.logURL = logURL ?? AppPaths.daemonLogURL()
        self.sessions = SessionTable(
            fileURL: sessionsURL ?? SessionTable.defaultURL(),
            ringLines: tuning.ringLines,
            ringByteCapacity: tuning.ringByteCapacity
        )
        self.lastEmptyAt = clock.now()
    }

    func start() throws {
        try sessions.restore()
        if !sessions.isEmpty {
            markOccupied()
        }
        try listener.bindAndListen()
        generation = try generationStore.bump()
        let source = DispatchSource.makeReadSource(
            fileDescriptor: listener.fileDescriptor,
            queue: DispatchQueue(label: "agent-room-terminal.daemon.accept")
        )
        source.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        acceptSource = source
        source.resume()
        startIdleTimer()
    }

    func waitUntilStopped() {
        stopSemaphore.wait()
    }

    func stop() {
        lock.lock()
        let already = stopped
        stopped = true
        lock.unlock()
        guard !already else { return }
        acceptSource?.cancel()
        idleSource?.cancel()
        closeAllSessions()
        proxies.stopAll()
        listener.close()
        stopSemaphore.signal()
    }

    @discardableResult
    func pollIdle() -> Bool {
        lock.lock()
        let empty = sessions.isEmpty
        let idle = tuning.idleSeconds
        let last = lastEmptyAt
        lock.unlock()
        guard empty, let last else { return false }
        let elapsed = clock.now().timeIntervalSince(last)
        if elapsed >= idle {
            stop()
            return true
        }
        return false
    }

    func handle(_ request: DaemonRequest) -> DaemonResponse {
        if let denied = authorize(request) {
            return denied
        }
        switch request.op {
        case .openSession:
            return openSession(request)
        case .ensureNetworkProxy:
            return ensureNetworkProxy(request)
        case .closeSession:
            return closeSession(request)
        case .exec:
            return exec(request)
        case .snapshot:
            return snapshot(request)
        case .listSessions:
            return listSessions()
        case .tuning:
            return tuning(request)
        case .input:
            return input(request)
        case .attach:
            return attach(request)
        case .resize:
            return resize(request)
        case .events:
            return events(request)
        }
    }

    private func acceptOne() {
        lock.lock()
        let done = stopped
        lock.unlock()
        if done { return }
        do {
            let client = try listener.acceptClient()
            lock.lock()
            consecutiveAcceptFailures = 0
            lock.unlock()
            let bits = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
            serveQueue.async {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: bits) else { return }
                let server = Unmanaged<DaemonServer>.fromOpaque(pointer).takeUnretainedValue()
                server.serve(client: client)
            }
        } catch {
            DaemonLog.append("accept-failed: \(DaemonLog.describe(error))", to: logURL)
            lock.lock()
            consecutiveAcceptFailures += 1
            let failures = consecutiveAcceptFailures
            lock.unlock()
            if failures >= Self.acceptFailureCircuitBreaker {
                DaemonLog.append(
                    "accept-circuit-breaker: \(failures) consecutive failures, attempting rebind",
                    to: logURL)
                attemptRebind()
            }
        }
    }

    private func attemptRebind() {
        acceptSource?.cancel()
        do {
            try listener.rebind()
            let source = DispatchSource.makeReadSource(
                fileDescriptor: listener.fileDescriptor,
                queue: DispatchQueue(label: "agent-room-terminal.daemon.accept")
            )
            source.setEventHandler { [weak self] in
                self?.acceptOne()
            }
            acceptSource = source
            source.resume()
            lock.lock()
            consecutiveAcceptFailures = 0
            lock.unlock()
            DaemonLog.append("accept-circuit-breaker: rebind succeeded", to: logURL)
        } catch {
            DaemonLog.append(
                "accept-circuit-breaker: rebind failed, exiting: \(DaemonLog.describe(error))",
                to: logURL)
            _exit(1)
        }
    }

    private func serve(client: Int32) {
        do {
            let payload = try UnixSocketIO.readFrame(fd: client)
            let request = try DaemonFraming.decodeRequest(payload)
            let response = handle(request)
            try writeEncoded(response, to: client)
            if request.op == .attach, response.ok {
                runAttachStream(client: client, request: request)
                return
            }
            if request.op == .events, response.ok {
                runEventsStream(client: client, request: request)
                return
            }
            Darwin.close(client)
        } catch UnixSocketIOError.closed {
            Darwin.close(client)
        } catch {
            reportSocketError(error, client: client)
            Darwin.close(client)
        }
    }

    private func runAttachStream(client: Int32, request: DaemonRequest) {
        guard let sessionID = request.sessionID, let session = sessionTable().get(sessionID) else {
            reportSocketError(
                DaemonProtocolError.requestFailed("unknown session"),
                client: client
            )
            Darwin.close(client)
            return
        }
        let stream = AttachConnection(client: client, logURL: logURL, generation: generation)
        let subID = subscribeAttach(
            session: session,
            sessionID: sessionID,
            stream: stream,
            replayBytes: request.replayBytes
        )
        defer {
            session.unsubscribe(subID)
            stream.close()
        }
        if session.hasExited {
            stream.send(
                makeExitFrame(
                    sessionID: sessionID,
                    code: session.recordedExitCode,
                    generation: generation
                )
            )
            return
        }
        pumpAttachInput(client: client, sessionID: sessionID, session: session, stream: stream)
    }

    private func subscribeAttach(
        session: PtyTerminalSession,
        sessionID: String,
        stream: AttachConnection,
        replayBytes: Int? = nil
    ) -> UUID {
        session.subscribe(
            replayBytes: replayBytes,
            onReplay: { data in
                stream.send(
                    makeReplayFrame(
                        sessionID: sessionID,
                        data: data,
                        generation: stream.generation
                    )
                )
            },
            onReplayEnd: {
                stream.send(
                    makeReplayEndFrame(
                        sessionID: sessionID,
                        generation: stream.generation
                    )
                )
            },
            onOutput: { data in
                stream.send(
                    makeOutputFrame(
                        sessionID: sessionID,
                        data: data,
                        generation: stream.generation
                    )
                )
            },
            onExit: { code in
                stream.send(
                    makeExitFrame(
                        sessionID: sessionID,
                        code: code,
                        generation: stream.generation
                    )
                )
                stream.shutdownRead()
                stream.close()
            }
        )
    }

    private func pumpAttachInput(
        client: Int32,
        sessionID: String,
        session: PtyTerminalSession,
        stream: AttachConnection
    ) {
        let socketStream = UnixSocketIO.SocketStream(fd: client)
        while !stream.isClosed {
            do {
                let payload = try socketStream.readFrame()
                let incoming = try DaemonFraming.decodeRequest(payload)
                if incoming.op == .input {
                    handleAttachInput(incoming, attachedSessionID: sessionID, session: session)
                }
            } catch UnixSocketIOError.closed {
                return
            } catch {
                reportSocketError(error, client: client)
                return
            }
        }
    }

    private func handleAttachInput(
        _ incoming: DaemonRequest,
        attachedSessionID: String,
        session: PtyTerminalSession
    ) {
        let targetID = incoming.sessionID ?? attachedSessionID
        guard targetID == attachedSessionID else { return }
        if let blob = incoming.bytes, let data = Data(base64Encoded: blob) {
            session.send(data)
            return
        }
        if let text = incoming.input {
            session.send(text)
        }
    }



    private func writeEncoded(_ value: some Encodable, to client: Int32) throws {
        let frame = try DaemonFraming.encode(value)
        try UnixSocketIO.writeAll(fd: client, data: frame)
    }

    func reportSocketError(_ error: Error, client: Int32) {
        let message = DaemonLog.describe(error)
        DaemonLog.append("socket-error: \(message)", to: logURL)
        let response = DaemonResponse.failure(message, generation: generation)
        do {
            try writeEncoded(response, to: client)
        } catch {
            DaemonLog.append(
                "socket-error-write-failed: \(DaemonLog.describe(error))",
                to: logURL
            )
        }
    }

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "agent-room-terminal.daemon.idle")
        )
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            _ = self?.pollIdle()
        }
        idleSource = timer
        timer.resume()
    }

    func markOccupied() {
        lock.lock()
        lastEmptyAt = nil
        lock.unlock()
    }

    func markEmptyIfNeeded() {
        lock.lock()
        if sessions.isEmpty {
            lastEmptyAt = clock.now()
        }
        lock.unlock()
    }

    func sessionTable() -> SessionTable { sessions }

    private func closeAllSessions() {
        for session in sessions.all() {
            session.close(grace: DaemonDefaults.closeGraceSeconds)
            _ = sessions.remove(session.sessionID)
        }
    }
}

private func makeOutputFrame(
    sessionID: String,
    data: Data,
    generation: UInt64
) -> DaemonStreamFrame {
    DaemonStreamFrame(
        generation: generation,
        event: DaemonStreamEventName.output,
        sessionID: sessionID,
        bytes: data.base64EncodedString()
    )
}

private func makeReplayFrame(
    sessionID: String,
    data: Data,
    generation: UInt64
) -> DaemonStreamFrame {
    DaemonStreamFrame(
        generation: generation,
        event: DaemonStreamEventName.replay,
        sessionID: sessionID,
        bytes: data.base64EncodedString()
    )
}

private func makeReplayEndFrame(
    sessionID: String,
    generation: UInt64
) -> DaemonStreamFrame {
    DaemonStreamFrame(
        generation: generation,
        event: DaemonStreamEventName.replayEnd,
        sessionID: sessionID
    )
}

private func makeExitFrame(
    sessionID: String,
    code: Int32,
    generation: UInt64
) -> DaemonStreamFrame {
    DaemonStreamFrame(
        generation: generation,
        event: DaemonStreamEventName.exited,
        sessionID: sessionID,
        code: Int(code)
    )
}

final class AttachConnection {
    let client: Int32
    let logURL: URL
    let generation: UInt64
    private let lock = NSLock()
    private var closed = false

    init(client: Int32, logURL: URL, generation: UInt64) {
        self.client = client
        self.logURL = logURL
        self.generation = generation
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    @discardableResult
    func send(_ payload: some Encodable) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        do {
            let frame = try DaemonFraming.encode(payload)
            try UnixSocketIO.writeAll(fd: client, data: frame)
            return true
        } catch {
            DaemonLog.append("attach-write-failed: \(DaemonLog.describe(error))", to: logURL)
            closed = true
            Darwin.close(client)
            return false
        }
    }

    func shutdownRead() {
        lock.lock()
        let already = closed
        lock.unlock()
        if !already {
            shutdown(client, SHUT_RD)
        }
    }

    func close() {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        if !already {
            Darwin.close(client)
        }
    }
}
