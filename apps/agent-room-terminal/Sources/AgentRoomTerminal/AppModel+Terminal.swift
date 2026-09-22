import Foundation
import AppKit
import AgentRoomTerminalCore
import TerminalEngineKit
import TerminalEngineGhostty

extension AppModel {
    func attachTerminalEngine(for room: RoomSummary, in container: NSView) {
        // 이전 방들의 엔진 서피스는 숨김 (뷰는 분리하지 않고 GPU 서피스만 숨김)
        for (id, eng) in terminalCache.engines where id != room.id {
            eng.isViewHidden = true
        }

        let engine: GhosttyTerminalEngine
        if let existing = terminalCache.engines[room.id] {
            engine = existing
            engine.isViewHidden = false
        } else {
            engine = createEngine(for: room)
        }

        let engineView = engine.view
        if engineView.superview !== container {
            engineView.removeFromSuperview()
            engineView.frame = container.bounds
            engineView.autoresizingMask = [.width, .height]
            container.addSubview(engineView)
        }
        engine.startIfNeeded()
        engine.makeFirstResponder()
    }

    private func createEngine(for room: RoomSummary) -> GhosttyTerminalEngine {
        let stream = TerminalByteStream()
        let newEngine = GhosttyTerminalEngine(stream: stream)
        terminalCache.engines[room.id] = newEngine

        let observer = TerminalEngineEventObserver(
            onBell: { [weak self] in
                self?.hasWaitingEvent[room.id] = true
            },
            onPause: { [weak self] in
                self?.hasWaitingEvent[room.id] = true
            },
            onTerminate: { [weak self] in
                self?.processTerminated[room.id] = true
            }
        )
        newEngine.eventsDelegate = observer
        terminalCache.observers[room.id] = observer

        newEngine.onProcessTerminated = { [weak self] in
            self?.processTerminated[room.id] = true
        }

        if let sessionID = room.sessionID {
            connectBridge(sessionID: sessionID, roomID: room.id, stream: stream)
        }

        return newEngine
    }

    private func connectBridge(sessionID: String, roomID: String, stream: TerminalByteStream) {
        let client = daemonClient ?? DaemonClient(
            socketURL: AppPaths.daemonSocketURL(),
            spawnIfMissing: false
        )
        let bridge = RoomTerminalBridge(
            sessionID: sessionID,
            client: client,
            stream: stream
        )
        bridge.onByteReceived = { [weak self] in
            Task { @MainActor in
                self?.lastByteReceived[roomID] = Date()
            }
        }
        bridge.onReconnecting = { [weak self] in
            Task { @MainActor in
                // 재접속 중에는 에러가 아닌 재접속 상태 유지
                self?.attachErrors[roomID] = false
            }
        }
        bridge.onReconnected = { [weak self] in
            Task { @MainActor in
                self?.attachErrors[roomID] = false
            }
        }
        bridge.onError = { [weak self] _ in
            Task { @MainActor in
                self?.attachErrors[roomID] = true
            }
        }
        bridge.onExit = { [weak self] in
            Task { @MainActor in
                self?.processTerminated[roomID] = true
            }
        }
        let originalOnInput = stream.onInput
        stream.onInput = { [weak self] data in
            Task { @MainActor in
                self?.hasWaitingEvent[roomID] = false
            }
            originalOnInput?(data)
        }
        terminalCache.bridges[roomID] = bridge
        bridge.start()
    }
}

final class TerminalEngineEventObserver: TerminalEngineEvents, Sendable {
    private let onBell: @MainActor @Sendable () -> Void
    private let onPause: @MainActor @Sendable () -> Void
    private let onTerminate: @MainActor @Sendable () -> Void

    init(
        onBell: @escaping @MainActor @Sendable () -> Void,
        onPause: @escaping @MainActor @Sendable () -> Void,
        onTerminate: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onBell = onBell
        self.onPause = onPause
        self.onTerminate = onTerminate
    }

    func terminalDidRingBell() {
        Task { @MainActor in
            onBell()
        }
    }

    func terminalDidReportProgress(state: TerminalProgressState, percent: Int?) {
        if state == .pause {
            Task { @MainActor in
                onPause()
            }
        }
    }

    func terminalProcessDidTerminate(exitCode: Int?) {
        Task { @MainActor in
            onTerminate()
        }
    }

    func terminalDidClose(processAlive: Bool) {
        Task { @MainActor in
            onTerminate()
        }
    }
}
