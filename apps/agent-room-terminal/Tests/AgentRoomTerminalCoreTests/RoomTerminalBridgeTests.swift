import Foundation
import os
import Testing
import TerminalEngineKit
@testable import AgentRoomTerminalCore

private final class FakeDaemonClient: DaemonTerminalSessionClient, Sendable {
    struct ResizeCall: Equatable, Sendable {
        var sessionID: String
        var columns: Int
        var rows: Int
    }

    struct InputCall: Equatable, Sendable {
        var sessionID: String
        var bytes: Data
    }

    private struct State: Sendable {
        var resizes: [ResizeCall] = []
        var inputs: [InputCall] = []
        var replayBytesRequested: [Int] = []
        var replayChunks: [Data] = []
        var liveChunks: [Data] = []
        var shouldFailAttach: Bool = false
        var failAttachCount: Int = 0
        var shouldFailInput: Bool = false
        var shouldFailResize: Bool = false
        var attachCount: Int = 0
        var holdOpen: Bool = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let holdSemaphore = DispatchSemaphore(value: 0)

    var replayChunks: [Data] {
        get { state.withLock { $0.replayChunks } }
        set { state.withLock { $0.replayChunks = newValue } }
    }

    var liveChunks: [Data] {
        get { state.withLock { $0.liveChunks } }
        set { state.withLock { $0.liveChunks = newValue } }
    }

    var shouldFailAttach: Bool {
        get { state.withLock { $0.shouldFailAttach } }
        set { state.withLock { $0.shouldFailAttach = newValue } }
    }

    var failAttachCount: Int {
        get { state.withLock { $0.failAttachCount } }
        set { state.withLock { $0.failAttachCount = newValue } }
    }

    var shouldFailInput: Bool {
        get { state.withLock { $0.shouldFailInput } }
        set { state.withLock { $0.shouldFailInput = newValue } }
    }

    var shouldFailResize: Bool {
        get { state.withLock { $0.shouldFailResize } }
        set { state.withLock { $0.shouldFailResize = newValue } }
    }

    var holdOpen: Bool {
        get { state.withLock { $0.holdOpen } }
        set { state.withLock { $0.holdOpen = newValue } }
    }

    func releaseHold() {
        holdSemaphore.signal()
    }

    var attachCount: Int { state.withLock { $0.attachCount } }
    var resizes: [ResizeCall] { state.withLock { $0.resizes } }
    var inputs: [InputCall] { state.withLock { $0.inputs } }
    var replayBytesRequested: [Int] { state.withLock { $0.replayBytesRequested } }

    func attachRaw(
        sessionID: String,
        replayBytes: Int,
        onBytes: (Data) throws -> Void,
        onReplayEnd: (() throws -> Void)?
    ) throws {
        let (fail, shouldHold) = state.withLock { s -> (Bool, Bool) in
            s.attachCount += 1
            s.replayBytesRequested.append(replayBytes)
            if s.shouldFailAttach {
                return (true, false)
            }
            if s.failAttachCount > 0 {
                s.failAttachCount -= 1
                return (true, false)
            }
            return (false, s.holdOpen)
        }

        if fail {
            throw DaemonProtocolError.requestFailed("simulated attach failure")
        }

        let replays = replayChunks
        for chunk in replays {
            try onBytes(chunk)
        }
        try onReplayEnd?()
        let lives = liveChunks
        for chunk in lives {
            try onBytes(chunk)
        }

        if shouldHold {
            holdSemaphore.wait()
        }
    }

    func resize(sessionID: String, columns: Int, rows: Int) throws {
        if state.withLock({ $0.shouldFailResize }) {
            throw DaemonProtocolError.requestFailed("simulated resize failure")
        }
        state.withLock { $0.resizes.append(ResizeCall(sessionID: sessionID, columns: columns, rows: rows)) }
    }

    func sendInput(sessionID: String, bytes: Data) throws {
        if state.withLock({ $0.shouldFailInput }) {
            throw DaemonProtocolError.requestFailed("simulated input failure")
        }
        state.withLock { $0.inputs.append(InputCall(sessionID: sessionID, bytes: bytes)) }
    }
}

@Suite("RoomTerminalBridge — 데몬과 터미널 엔진 간 바이트 스트림 배선")
struct RoomTerminalBridgeTests {
    @Test("리플레이 바이트는 모아서 onReplayEnd 시점에 한 번에 전달하고 이후 바이트는 실시간 전달한다")
    func testReplayAndLiveBytes() {
        let fake = FakeDaemonClient()
        fake.replayChunks = [Data("chunk1".utf8), Data("chunk2".utf8)]
        fake.liveChunks = [Data("live".utf8)]

        let stream = TerminalByteStream()
        let received = OSAllocatedUnfairLock(initialState: [Data]())
        stream.receiveHandler = { data in
            received.withLock { $0.append(data) }
        }

        let bridge = RoomTerminalBridge(
            sessionID: "test-session-1",
            client: fake,
            stream: stream,
            replayBytes: 1234
        )

        bridge.runSync()

        let chunks = received.withLock { $0 }
        #expect(chunks.count == 2)
        #expect(chunks[0] == Data("chunk1chunk2".utf8))
        #expect(chunks[1] == Data("live".utf8))
        #expect(fake.replayBytesRequested == [1234])
    }

    @Test("stream.onInput 과 stream.onResize 가 데몬 클라이언트로 정확히 전달된다")
    func testInputAndResizeForwarding() {
        let fake = FakeDaemonClient()
        let stream = TerminalByteStream()
        _ = RoomTerminalBridge(
            sessionID: "test-session-2",
            client: fake,
            stream: stream
        )

        let inputData = Data("ls -la\n".utf8)
        stream.sendInput(inputData)

        #expect(fake.inputs.count == 1)
        #expect(fake.inputs.first == FakeDaemonClient.InputCall(sessionID: "test-session-2", bytes: inputData))

        stream.onResize?(120, 35)

        #expect(fake.resizes.count == 1)
        #expect(fake.resizes.first == FakeDaemonClient.ResizeCall(sessionID: "test-session-2", columns: 120, rows: 35))
    }

    @Test("onInput 및 onResize 실패 시 onError 로 오류가 전파된다")
    func testInputAndResizeErrorForwarding() {
        let fake = FakeDaemonClient()
        fake.shouldFailInput = true
        fake.shouldFailResize = true
        let stream = TerminalByteStream()
        let bridge = RoomTerminalBridge(
            sessionID: "test-session-err-fwd",
            client: fake,
            stream: stream
        )

        let capturedErrors = OSAllocatedUnfairLock<[Error]>(initialState: [])
        bridge.onError = { err in
            capturedErrors.withLock { $0.append(err) }
        }

        // input 에러
        stream.sendInput(Data("test".utf8))
        #expect(capturedErrors.withLock { $0.count } == 1)

        // resize 에러
        stream.onResize?(80, 24)
        #expect(capturedErrors.withLock { $0.count } == 2)
    }

    @Test("handleExit 에 넘겨진 exitCode 가 stream.finish 로 정확히 전달된다")
    func testExitCodeForwarding() {
        let fake = FakeDaemonClient()
        let stream = TerminalByteStream()
        let exitCodeCaptured = OSAllocatedUnfairLock<Int?>(initialState: nil)
        stream.finishHandler = { code in
            exitCodeCaptured.withLock { $0 = code }
        }

        let bridge = RoomTerminalBridge(
            sessionID: "test-session-exit",
            client: fake,
            stream: stream
        )

        bridge.runSync(exitCode: 42)

        #expect(exitCodeCaptured.withLock { $0 } == 42)
    }

    @Test("disconnect 호출 후 이전 비동기 attach 콜백은 무시된다")
    func testCancellationIgnoresCallbacks() {
        let fake = FakeDaemonClient()
        let stream = TerminalByteStream()
        let received = OSAllocatedUnfairLock(initialState: [Data]())
        stream.receiveHandler = { data in
            received.withLock { $0.append(data) }
        }

        let bridge = RoomTerminalBridge(
            sessionID: "test-session-cancel",
            client: fake,
            stream: stream
        )

        bridge.start()
        bridge.disconnect()

        #expect(!bridge.isConnected)
    }

    @Test("attach 실패 시 재접속 백오프 후 최대 횟수 초과 시 onError 호출")
    func testReconnectBackoffThenError() async {
        let fake = FakeDaemonClient()
        fake.shouldFailAttach = true
        let stream = TerminalByteStream()
        let bridge = RoomTerminalBridge(
            sessionID: "test-session-backoff",
            client: fake,
            stream: stream,
            backoffDelays: [0.01, 0.02],
            maxReconnectAttempts: 2
        )

        let reconnectingCalls = OSAllocatedUnfairLock(initialState: 0)
        let errorCaptured = OSAllocatedUnfairLock<Error?>(initialState: nil)

        bridge.onReconnecting = {
            reconnectingCalls.withLock { $0 += 1 }
        }
        bridge.onError = { err in
            errorCaptured.withLock { $0 = err }
        }

        bridge.start()

        // 2회 백오프 대기 (CI 러너 부하 감안 폴링 루프)
        for _ in 0..<30 {
            if errorCaptured.withLock({ $0 != nil }) && reconnectingCalls.withLock({ $0 >= 2 }) {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(reconnectingCalls.withLock { $0 } >= 2)
        #expect(errorCaptured.withLock { $0 } != nil)
    }

    @Test("재접속 시도 후 성공하면 onReconnected 가 호출된다")
    func testReconnectSuccess() async {
        let fake = FakeDaemonClient()
        fake.holdOpen = true
        defer { fake.releaseHold() }
        // 1번 실패 후 2번째 시도에서 성공하도록 설정
        fake.failAttachCount = 1
        fake.liveChunks = [Data("recovered".utf8)]

        let stream = TerminalByteStream()
        let bridge = RoomTerminalBridge(
            sessionID: "test-session-recover",
            client: fake,
            stream: stream,
            backoffDelays: [0.01, 0.02],
            maxReconnectAttempts: 3
        )

        let reconnected = OSAllocatedUnfairLock(initialState: false)
        bridge.onReconnected = {
            reconnected.withLock { $0 = true }
        }

        bridge.start()

        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(reconnected.withLock { $0 })
        #expect(bridge.isConnected)
    }
}
