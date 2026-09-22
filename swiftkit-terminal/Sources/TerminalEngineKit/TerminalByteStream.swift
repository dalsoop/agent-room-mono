import Foundation
import os

/// 터미널 바이트 스트림 통신 계약.
/// 호스트(PTY, 네트워크 세션, 가상 시뮬레이터 등)와 터미널 엔진 사이의 양방향 바이트 입출력 채널.
public final class TerminalByteStream: Sendable {
    private struct State: Sendable {
        var onInput: (@Sendable (Data) -> Void)?
        var onResize: (@Sendable (_ columns: Int, _ rows: Int) -> Void)?
        var receiveHandler: (@Sendable (Data) -> Void)?
        var resizeHandler: (@Sendable (_ columns: Int, _ rows: Int) -> Void)?
        var finishHandler: (@Sendable (_ exitCode: Int) -> Void)?
        var bufferedReceives: [Data] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    /// 터미널 서피스에서 발생한 사용자 입력(키 입력/붙여넣기) 바이트 콜백
    public var onInput: (@Sendable (Data) -> Void)? {
        get { state.withLock { $0.onInput } }
        set { state.withLock { $0.onInput = newValue } }
    }

    /// 터미널 서피스 리사이즈(컬럼, 행) 알림 콜백
    public var onResize: (@Sendable (_ columns: Int, _ rows: Int) -> Void)? {
        get { state.withLock { $0.onResize } }
        set { state.withLock { $0.onResize = newValue } }
    }

    public var receiveHandler: (@Sendable (Data) -> Void)? {
        get { state.withLock { $0.receiveHandler } }
        set {
            let pending: [Data] = state.withLock { s in
                s.receiveHandler = newValue
                let buf = s.bufferedReceives
                s.bufferedReceives.removeAll()
                return buf
            }
            if let handler = newValue {
                for data in pending {
                    handler(data)
                }
            }
        }
    }

    public var resizeHandler: (@Sendable (_ columns: Int, _ rows: Int) -> Void)? {
        get { state.withLock { $0.resizeHandler } }
        set { state.withLock { $0.resizeHandler = newValue } }
    }

    public var finishHandler: (@Sendable (_ exitCode: Int) -> Void)? {
        get { state.withLock { $0.finishHandler } }
        set { state.withLock { $0.finishHandler = newValue } }
    }

    public init(
        onInput: (@Sendable (Data) -> Void)? = nil,
        onResize: (@Sendable (_ columns: Int, _ rows: Int) -> Void)? = nil
    ) {
        self.state = OSAllocatedUnfairLock(initialState: State(onInput: onInput, onResize: onResize))
    }

    /// 호스트로부터 터미널 엔진으로 수신된 바이트를 주입한다.
    public func receive(_ data: Data) {
        let handler = state.withLock { s -> (@Sendable (Data) -> Void)? in
            if let h = s.receiveHandler {
                return h
            } else {
                s.bufferedReceives.append(data)
                return nil
            }
        }
        handler?(data)
    }

    /// 호스트로부터 터미널 엔진으로 UTF-8 문자열을 주입한다.
    public func receive(_ text: String) {
        if let data = text.data(using: .utf8) {
            receive(data)
        }
    }

    /// 호스트 측 버퍼/PTY 크기 변경을 터미널 엔진에 전달한다.
    public func resize(columns: Int, rows: Int) {
        let handler = state.withLock { $0.resizeHandler }
        handler?(columns, rows)
    }

    /// 호스트 프로세스 종료 알림을 터미널 엔진에 전송한다.
    public func finish(exitCode: Int = 0) {
        let handler = state.withLock { $0.finishHandler }
        handler?(exitCode)
    }

    /// 터미널 서피스로부터 호스트 측으로 입력 바이트를 전달한다.
    public func sendInput(_ data: Data) {
        let handler = state.withLock { $0.onInput }
        handler?(data)
    }
}
