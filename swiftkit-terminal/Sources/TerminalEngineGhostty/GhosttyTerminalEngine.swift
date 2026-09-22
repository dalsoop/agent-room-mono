#if canImport(AppKit)
import AppKit
import Foundation
import GhosttyKit
import GhosttyTerminal
import TerminalEngineKit

/// Ghostty의 C/Zig 기반 Metal 120Hz GPU 렌더러(`libghostty-spm`)를 구동하는 터미널 엔진 구현체.
/// 대화형 PTY 세션(exec 백엔드) 및 가상 바이트 스트림(inMemory 백엔드)을 모두 지원한다.
@MainActor
public final class GhosttyTerminalEngine: NSObject, TerminalEngine,
    TerminalSurfaceViewDelegate,
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceProgressReportDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfacePwdDelegate
{
    public let termView: AppTerminalView
    public let launch: TerminalLaunch?
    public let stream: TerminalByteStream?
    public let inMemorySession: InMemoryTerminalSession?
    public private(set) var appearance: TerminalAppearance
    private var started = false
    private var pendingSends: [String] = []

    public var view: TerminalPlatformView { termView }

    public var isViewHidden: Bool {
        get { termView.isHidden }
        set {
            termView.isHidden = newValue
            termView.setSurfaceVisible(!newValue)
        }
    }

    public var onProcessTerminated: (() -> Void)?
    public weak var eventsDelegate: (any TerminalEngineEvents)?

    /// Exec 백엔드 생성자 — PTY 프로세스 직접 구동.
    public init(launch: TerminalLaunch) {
        self.launch = launch
        self.stream = nil
        self.inMemorySession = nil
        self.appearance = launch.appearance
        self.termView = AppTerminalView(frame: .zero)
        super.init()

        self.termView.autoresizingMask = [.width, .height]
        self.termView.controller = GhosttyTerminal.TerminalController.shared
        self.termView.delegate = self

        let envDict: [String: String]
        if let sandbox = launch.sandbox {
            envDict = sandbox.environment
        } else {
            envDict = launch.environment
        }

        let launchCommand = Self.resolveLaunchCommand(launch: launch)
        let options = TerminalSurfaceOptions(
            backend: .exec,
            fontSize: Float(launch.appearance.fontSize),
            workingDirectory: launch.cwd,
            envVars: envDict,
            command: launchCommand,
            context: .window
        )
        self.termView.configuration = options
    }

    /// In-Memory 백엔드 생성자 — 호스트 `TerminalByteStream`과 양방향 연결.
    public init(stream: TerminalByteStream, appearance: TerminalAppearance = .default) {
        self.launch = nil
        self.stream = stream
        self.appearance = appearance
        self.termView = AppTerminalView(frame: .zero)

        let inMem = InMemoryTerminalSession(
            write: { [weak stream] data in
                stream?.sendInput(data)
            },
            resize: { [weak stream] viewport in
                stream?.onResize?(Int(viewport.columns), Int(viewport.rows))
            }
        )
        self.inMemorySession = inMem
        super.init()

        // 호스트 -> 인메모리 세션 연결
        stream.receiveHandler = { [weak inMem] data in
            inMem?.receive(data)
        }
        stream.finishHandler = { [weak inMem] exitCode in
            inMem?.finish(exitCode: UInt32(exitCode), runtimeMilliseconds: 0)
        }

        self.termView.autoresizingMask = [.width, .height]
        self.termView.controller = GhosttyTerminal.TerminalController.shared
        self.termView.delegate = self

        let options = TerminalSurfaceOptions(
            backend: .inMemory(inMem),
            fontSize: Float(appearance.fontSize),
            context: .window
        )
        self.termView.configuration = options
    }

    /// In-Memory 모드에서 활성 뷰포트 텍스트 읽기
    public func readViewportText() -> String? {
        inMemorySession?.readViewportText()
    }

    /// In-Memory 모드에서 대기 중인 출력 파싱이 모두 끝날 때까지 대기
    public func waitForPendingOutput() {
        inMemorySession?.waitForPendingOutput()
    }

    /// 설정 파일 핫리로드 적용
    public static func updateConfigFile(_ path: String) {
        if FileManager.default.fileExists(atPath: path) {
            GhosttyTerminal.TerminalController.shared.updateConfigSource(.file(path))
        }
    }

    public func applyAppearance(_ appearance: TerminalAppearance) {
        self.appearance = appearance
        termView.configuration.fontSize = Float(appearance.fontSize)
    }

    public func send(text: String) {
        if !termView.paste(text: text) {
            if let inMem = inMemorySession, let data = text.data(using: .utf8) {
                inMem.sendInput(data)
            } else {
                pendingSends.append(text)
            }
        }
    }

    public func makeFirstResponder() {
        if !termView.acquireProgrammaticFocus() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                _ = self.termView.acquireProgrammaticFocus()
            }
        }
    }

    public func containsPointInWindow(_ point: CGPoint) -> Bool {
        guard termView.window != nil, !termView.isHiddenOrHasHiddenAncestor else {
            return false
        }
        return termView.bounds.contains(termView.convert(point, from: nil))
    }

    public func startIfNeeded() {
        guard !started else { return }
        started = true

        applyAppearance(appearance)
        termView.setSurfaceVisible(true)
        flushPendingSends()
        makeFirstResponder()
    }

    public func terminate() {
        termView.setSurfaceVisible(false)
        eventsDelegate?.terminalProcessDidTerminate(exitCode: nil)
    }

    private func flushPendingSends() {
        guard !pendingSends.isEmpty else { return }
        let toSend = pendingSends
        pendingSends.removeAll()
        for txt in toSend {
            send(text: txt)
        }
    }

    // MARK: - Delegate Handlers

    public func terminalDidChangeTitle(_ title: String) {
        eventsDelegate?.terminalDidChangeTitle(title)
    }

    public func terminalDidChangeWorkingDirectory(_ path: String) {
        eventsDelegate?.terminalDidChangeWorkingDirectory(path)
    }

    public func terminalDidRingBell() {
        eventsDelegate?.terminalDidRingBell()
    }

    public func terminalDidReportProgress(state: GhosttyTerminal.TerminalProgressState, percent: Int?) {
        let mapped: TerminalEngineKit.TerminalProgressState = switch state {
        case .remove: .remove
        case .set: .set
        case .error: .error
        case .indeterminate: .indeterminate
        case .pause: .pause
        }
        eventsDelegate?.terminalDidReportProgress(state: mapped, percent: percent)
    }

    public func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        eventsDelegate?.terminalDidFinishCommand(exitCode: exitCode, durationNanos: durationNanos)
    }

    public func terminalDidRequestDesktopNotification(title: String, body: String) {
        eventsDelegate?.terminalDidRequestDesktopNotification(title: title, body: body)
    }

    public func terminalDidClose(processAlive: Bool) {
        eventsDelegate?.terminalProcessDidTerminate(exitCode: nil)
        eventsDelegate?.terminalDidClose(processAlive: processAlive)
        Task { @MainActor in
            self.onProcessTerminated?()
        }
    }

    // MARK: - Launch Command Resolution

    private static func resolveLaunchCommand(launch: TerminalLaunch) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let rawCommand = launch.rawCommand {
            let inner = "exec " + rawCommand.map(Self.shq).joined(separator: " ")
            return "\(shell) -l -c \(shq(inner))"
        } else if let backing = launch.backing, let bin = backing.tmuxBin {
            let args = backing.launchArgs(
                name: launch.tmuxName ?? "terminal",
                cwd: launch.cwd,
                command: launch.command,
                shell: shell,
                sandbox: launch.sandbox
            )
            return ([bin] + args).map(Self.shq).joined(separator: " ")
        } else if !launch.command.isEmpty {
            let wrapped: [String]
            if let sandbox = launch.sandbox {
                wrapped = PaneEnvInjector.wrap(
                    command: launch.command,
                    shell: shell,
                    sandbox: sandbox
                )
            } else {
                wrapped = [shell, "-l", "-c", "exec " + launch.command.map(Self.shq).joined(separator: " ")]
            }
            return wrapped.map(Self.shq).joined(separator: " ")
        } else {
            return nil
        }
    }

    private static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// 팩토리 확장 등록
extension TerminalEngineFactory {
    public static func registerGhostty() {
        register(.ghostty) { launch in
            GhosttyTerminalEngine(launch: launch)
        }
    }
}

// 하위 호환 별칭
public typealias GhosttyEngineSession = GhosttyTerminalEngine
#endif
