#if canImport(AppKit)
import AppKit
import Foundation
import SwiftTerm
import TerminalEngineKit

/// `SwiftTerm` 라이브러리로 PTY 프로세스를 구동하고 화면을 렌더링하는 엔진 구현체.
@MainActor
public final class SwiftTermTerminalEngine: TerminalEngine {
    public let termView: InteractiveTerminalView
    private let launch: TerminalLaunch
    private var started = false

    public var view: TerminalPlatformView { termView }

    public var isViewHidden: Bool {
        get { termView.isHidden }
        set { termView.isHidden = newValue }
    }

    public var onProcessTerminated: (() -> Void)?
    public weak var eventsDelegate: (any TerminalEngineEvents)?

    public init(launch: TerminalLaunch) {
        self.launch = launch
        let tv = InteractiveTerminalView(frame: .zero)
        tv.autoresizingMask = [.width, .height]
        tv.optionAsMetaKey = launch.appearance.macosOptionAsAlt
        self.termView = tv

        setupEventForwarding()
    }

    private func setupEventForwarding() {
        termView.onTitleChanged = { [weak self] title in
            self?.eventsDelegate?.terminalDidChangeTitle(title)
        }
        termView.onWorkingDirectoryChanged = { [weak self] dir in
            self?.eventsDelegate?.terminalDidChangeWorkingDirectory(dir)
        }
        termView.onBell = { [weak self] in
            self?.eventsDelegate?.terminalDidRingBell()
        }
    }

    public func applyAppearance(_ appearance: TerminalAppearance) {
        TerminalAppearanceApplier.apply(appearance, to: termView)
        termView.optionAsMetaKey = appearance.macosOptionAsAlt
    }

    public func send(text: String) {
        termView.send(txt: text)
    }

    public func makeFirstResponder() {
        if let window = termView.window, window.firstResponder !== termView {
            window.makeFirstResponder(termView)
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

        applyAppearance(launch.appearance)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let baseEnv = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let env: [String]
        if let sandbox = launch.sandbox {
            env = PaneEnvInjector.merge(base: baseEnv, sandbox: sandbox)
        } else {
            var combined = baseEnv
            for (k, v) in launch.environment {
                combined.append("\(k)=\(v)")
            }
            env = combined
        }

        if let rawCommand = launch.rawCommand {
            launchRawCommand(rawCommand, shell: shell, env: env)
        } else if let backing = launch.backing, let bin = backing.tmuxBin {
            launchTmux(backing: backing, bin: bin, shell: shell, env: env)
        } else {
            launchShellFallback(shell: shell, env: env)
        }
    }

    public func terminate() {
        termView.terminate()
        eventsDelegate?.terminalProcessDidTerminate(exitCode: nil)
        onProcessTerminated?()
    }

    private func launchRawCommand(_ rawCommand: [String], shell: String, env: [String]) {
        let inner = "exec " + rawCommand.map(Self.shq).joined(separator: " ")
        termView.startProcess(
            executable: shell,
            args: ["-l", "-c", inner],
            environment: env,
            currentDirectory: launch.cwd
        )
    }

    private func launchTmux(backing: TmuxBacking, bin: String, shell: String, env: [String]) {
        let args = backing.launchArgs(
            name: launch.tmuxName ?? "terminal",
            cwd: launch.cwd,
            command: launch.command,
            shell: shell,
            sandbox: launch.sandbox
        )
        termView.startProcess(
            executable: bin,
            args: args,
            environment: env,
            currentDirectory: launch.cwd
        )
    }

    private func launchShellFallback(shell: String, env: [String]) {
        let wrapped: [String]
        if let sandbox = launch.sandbox {
            wrapped = PaneEnvInjector.wrap(
                command: launch.command,
                shell: shell,
                sandbox: sandbox
            )
        } else if launch.command.isEmpty {
            wrapped = [shell, "-l"]
        } else {
            wrapped = [shell, "-l", "-c", "exec " + launch.command.map(Self.shq).joined(separator: " ")]
        }
        let exe = wrapped.first ?? shell
        let args = Array(wrapped.dropFirst())
        termView.startProcess(
            executable: exe,
            args: args,
            environment: env,
            currentDirectory: launch.cwd
        )
    }

    private static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// 팩토리 확장 등록
extension TerminalEngineFactory {
    public static func registerSwiftTerm() {
        register(.swiftTerm) { launch in
            SwiftTermTerminalEngine(launch: launch)
        }
    }
}

// 하위 호환 별칭
public typealias SwiftTermEngineSession = SwiftTermTerminalEngine
#endif
