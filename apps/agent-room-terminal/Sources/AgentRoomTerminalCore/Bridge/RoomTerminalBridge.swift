import Foundation
import os
import TerminalEngineKit

/// 데몬 터미널 세션 클라이언트 통신 계약.
/// DaemonClient 가 준수하며 가짜 클라이언트를 주입해 단위 테스트할 수 있다.
public protocol DaemonTerminalSessionClient: Sendable {
    func attachRaw(
        sessionID: String,
        replayBytes: Int,
        onBytes: (Data) throws -> Void,
        onReplayEnd: (() throws -> Void)?
    ) throws

    func resize(sessionID: String, columns: Int, rows: Int) throws
    func sendInput(sessionID: String, bytes: Data) throws
}

extension DaemonClient: DaemonTerminalSessionClient {}

/// 데몬 ↔ 터미널 엔진 배선 브리지.
/// - attachRaw 의 바이트를 stream.receive 로 주입
/// - onReplayEnd 까지는 화면 갱신을 버퍼에 모아서 한 번에 전달
/// - stream.onInput → daemon sendInput 전달 (실패 시 onError)
/// - stream.onResize → daemon resize 전달 (실패 시 onError)
/// - 데몬 재연결 시 replayBytes 로 되살림 (지수 백오프 1·2·4·8초, 최대 5회)
/// - disconnect 시 진행 중인 attach 취소 토큰으로 무시
/// - handleExit 에서 프레임의 code 를 받아 finish 로 전달
public final class RoomTerminalBridge: Sendable {
    public let sessionID: String
    public let client: any DaemonTerminalSessionClient
    public let stream: TerminalByteStream
    public let replayBytes: Int
    public let backoffDelays: [TimeInterval]
    public let maxReconnectAttempts: Int

    private struct Handlers: Sendable {
        var onByteReceived: (@Sendable () -> Void)?
        var onReplayFlushed: (@Sendable (Data) -> Void)?
        var onError: (@Sendable (any Error) -> Void)?
        var onExit: (@Sendable () -> Void)?
        var onReconnecting: (@Sendable () -> Void)?
        var onReconnected: (@Sendable () -> Void)?
    }

    private struct State: Sendable {
        var isReplaying = true
        var replayBuffer = Data()
        var isConnected = false
        var isReconnecting = false
        var lastByteAt: Date?
        var attachErrorMessage: String?
        var didExit = false
        var token = UUID()
        var reconnectAttempt = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let handlers = OSAllocatedUnfairLock(initialState: Handlers())
    private let queue = DispatchQueue(label: "net.ranode.agent-room-terminal.bridge", qos: .userInitiated)

    public var onByteReceived: (@Sendable () -> Void)? {
        get { handlers.withLock { $0.onByteReceived } }
        set { handlers.withLock { $0.onByteReceived = newValue } }
    }

    public var onReplayFlushed: (@Sendable (Data) -> Void)? {
        get { handlers.withLock { $0.onReplayFlushed } }
        set { handlers.withLock { $0.onReplayFlushed = newValue } }
    }

    public var onError: (@Sendable (any Error) -> Void)? {
        get { handlers.withLock { $0.onError } }
        set { handlers.withLock { $0.onError = newValue } }
    }

    public var onExit: (@Sendable () -> Void)? {
        get { handlers.withLock { $0.onExit } }
        set { handlers.withLock { $0.onExit = newValue } }
    }

    public var onReconnecting: (@Sendable () -> Void)? {
        get { handlers.withLock { $0.onReconnecting } }
        set { handlers.withLock { $0.onReconnecting = newValue } }
    }

    public var onReconnected: (@Sendable () -> Void)? {
        get { handlers.withLock { $0.onReconnected } }
        set { handlers.withLock { $0.onReconnected = newValue } }
    }

    public init(
        sessionID: String,
        client: any DaemonTerminalSessionClient,
        stream: TerminalByteStream = TerminalByteStream(),
        replayBytes: Int = DaemonDefaults.ringByteCapacity,
        backoffDelays: [TimeInterval] = [1.0, 2.0, 4.0, 8.0, 16.0],
        maxReconnectAttempts: Int = 5
    ) {
        self.sessionID = sessionID
        self.client = client
        self.stream = stream
        self.replayBytes = replayBytes
        self.backoffDelays = backoffDelays
        self.maxReconnectAttempts = maxReconnectAttempts

        setupStreamHandlers()
    }

    private func setupStreamHandlers() {
        let client = self.client
        let sessionID = self.sessionID

        stream.onInput = { [weak self] data in
            do {
                try client.sendInput(sessionID: sessionID, bytes: data)
            } catch {
                self?.handleError(error)
            }
        }

        stream.onResize = { [weak self] columns, rows in
            do {
                try client.resize(sessionID: sessionID, columns: columns, rows: rows)
            } catch {
                self?.handleError(error)
            }
        }
    }

    public var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    public var isReconnecting: Bool {
        state.withLock { $0.isReconnecting }
    }

    public var lastByteAt: Date? {
        state.withLock { $0.lastByteAt }
    }

    /// 비동기 백그라운드 attach 시작
    public func start() {
        let currentToken = state.withLock { s -> UUID in
            s.isConnected = true
            s.isReconnecting = false
            s.isReplaying = true
            s.replayBuffer.removeAll()
            s.attachErrorMessage = nil
            s.didExit = false
            s.reconnectAttempt = 0
            s.token = UUID()
            return s.token
        }

        performAttachAsync(token: currentToken)
    }

    private func performAttachAsync(token: UUID) {
        let sid = sessionID
        let replay = replayBytes
        let cli = client

        queue.async { [weak self] in
            guard let self, self.isTokenValid(token) else { return }
            do {
                try cli.attachRaw(
                    sessionID: sid,
                    replayBytes: replay,
                    onBytes: { [weak self] data in
                        self?.handleBytes(data, token: token)
                    },
                    onReplayEnd: { [weak self] in
                        self?.handleReplayEnd(token: token)
                    }
                )
                self.handleExit(token: token)
            } catch {
                self.handleAttachError(error, token: token)
            }
        }
    }

    /// 동기식 attach (단위 테스트 등 동기 실행용)
    public func runSync(exitCode: Int? = nil) {
        let currentToken = state.withLock { s -> UUID in
            s.isConnected = true
            s.isReconnecting = false
            s.isReplaying = true
            s.replayBuffer.removeAll()
            s.attachErrorMessage = nil
            s.didExit = false
            s.token = UUID()
            return s.token
        }

        do {
            try client.attachRaw(
                sessionID: sessionID,
                replayBytes: replayBytes,
                onBytes: { [weak self] data in
                    self?.handleBytes(data, token: currentToken)
                },
                onReplayEnd: { [weak self] in
                    self?.handleReplayEnd(token: currentToken)
                }
            )
            handleExit(code: exitCode, token: currentToken)
        } catch {
            handleAttachError(error, token: currentToken, isSync: true)
        }
    }

    public func reconnect() {
        disconnect()
        start()
    }

    public func disconnect() {
        state.withLock { s in
            s.isConnected = false
            s.isReconnecting = false
            s.isReplaying = true
            s.replayBuffer.removeAll()
            s.token = UUID() // 이전 콜백 무효화
            s.reconnectAttempt = 0
        }
    }

    private func isTokenValid(_ token: UUID) -> Bool {
        state.withLock { $0.token == token }
    }

    public func handleBytes(_ data: Data, token: UUID? = nil) {
        if let token, !isTokenValid(token) { return }

        let (shouldReceiveDirectly, wasReconnecting) = state.withLock { s -> (Bool, Bool) in
            let wasReconn = s.isReconnecting
            if s.isReconnecting {
                s.isReconnecting = false
                s.isConnected = true
                s.reconnectAttempt = 0
            }
            s.lastByteAt = Date()
            if s.isReplaying {
                s.replayBuffer.append(data)
                return (false, wasReconn)
            } else {
                return (true, wasReconn)
            }
        }

        if wasReconnecting {
            onReconnected?()
        }

        onByteReceived?()
        if shouldReceiveDirectly {
            stream.receive(data)
        }
    }

    public func handleReplayEnd(token: UUID? = nil) {
        if let token, !isTokenValid(token) { return }

        let (buffered, wasReconnecting) = state.withLock { s -> (Data, Bool) in
            let wasReconn = s.isReconnecting
            if s.isReconnecting {
                s.isReconnecting = false
                s.isConnected = true
                s.reconnectAttempt = 0
            }
            s.isReplaying = false
            let buf = s.replayBuffer
            s.replayBuffer.removeAll()
            return (buf, wasReconn)
        }

        if wasReconnecting {
            onReconnected?()
        }

        if !buffered.isEmpty {
            stream.receive(buffered)
            onReplayFlushed?(buffered)
        }
    }

    public func handleExit(code: Int? = nil, token: UUID? = nil) {
        if let token, !isTokenValid(token) { return }

        let alreadyExited: Bool = state.withLock { s in
            if s.didExit { return true }
            s.isConnected = false
            s.isReconnecting = false
            s.didExit = true
            return false
        }
        guard !alreadyExited else { return }

        stream.finish(exitCode: code ?? 0)
        onExit?()
    }

    public func handleError(_ error: Error) {
        state.withLock { s in
            s.isConnected = false
            s.isReconnecting = false
            s.attachErrorMessage = String(describing: error)
        }
        onError?(error)
    }

    private func handleAttachError(_ error: Error, token: UUID, isSync: Bool = false) {
        guard isTokenValid(token) else { return }

        let shouldRetry: (attempt: Int, delay: TimeInterval)? = state.withLock { s in
            guard !s.didExit else { return nil }
            if s.reconnectAttempt < maxReconnectAttempts {
                s.reconnectAttempt += 1
                s.isReconnecting = true
                s.isConnected = false
                s.isReplaying = true
                s.replayBuffer.removeAll()
                let delayIndex = min(s.reconnectAttempt - 1, backoffDelays.count - 1)
                let delay = delayIndex >= 0 ? backoffDelays[delayIndex] : 1.0
                return (s.reconnectAttempt, delay)
            } else {
                s.isConnected = false
                s.isReconnecting = false
                s.attachErrorMessage = String(describing: error)
                return nil
            }
        }

        if let retry = shouldRetry {
            onReconnecting?()
            if isSync {
                // 동기 실행에서는 재시도하지 않고 에러 처리
                handleError(error)
            } else {
                queue.asyncAfter(deadline: .now() + retry.delay) { [weak self] in
                    guard let self, self.isTokenValid(token) else { return }
                    self.performAttachAsync(token: token)
                }
            }
        } else {
            onError?(error)
        }
    }
}
