import Foundation
import CommandKit
import InteropKit
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit.terminal", category: "TmuxBacking")

/// 복귀 대상이 되는, 살아있는 tmux 세션 하나.
public struct TmuxBackedSession: Sendable, Equatable {
    public let name: String      // "<prefix>/<id>"
    public let cwd: String       // pane_current_path
    public let command: String   // pane_current_command (예: "claude")

    public init(name: String, cwd: String, command: String) {
        self.name = name; self.cwd = cwd; self.command = command
    }

    /// 세션 id 부분 (접두사 제거)
    public func shortId(prefix: String = "terminal/") -> String {
        name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }
}

/// 내장 터미널을 전용 tmux 서버(`-L <socket>`)로 뒷받침한다.
public struct TmuxBacking: Sendable {
    public static let defaultPrefix = "terminal/"
    public static let defaultSocket = "terminal"

    public let prefix: String
    public let socket: String
    public let configPath: String
    public let tmuxBin: String?
    private let runner: CommandRunning

    public init(
        prefix: String = defaultPrefix,
        socket: String = defaultSocket,
        configPath: String,
        tmuxBin: String? = TmuxBacking.findTmux(),
        runner: CommandRunning = ProcessCommandRunner()
    ) {
        self.prefix = prefix
        self.socket = socket
        self.configPath = configPath
        self.tmuxBin = tmuxBin
        self.runner = runner
    }

    /// tmux 로 뒷받침 가능한가(바이너리 존재).
    public var available: Bool { tmuxBin != nil }

    /// tmux 실행 파일 경로 탐색
    public static func findTmux() -> String? {
        for p in [HostPlatform.cliBinPath("tmux"), "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    // MARK: - 순수 argv/이름

    public func sessionName(_ id: String) -> String { prefix + id }
    public func isOurs(_ name: String) -> Bool { name.hasPrefix(prefix) }

    public static func sessionName(_ id: String, prefix: String = defaultPrefix) -> String { prefix + id }
    public static func isOurs(_ name: String, prefix: String = defaultPrefix) -> Bool { name.hasPrefix(prefix) }

    public static let baseConfigLines = [
        "set -g status off",
        "set -g escape-time 10",
        #"set -g default-terminal "xterm-256color""#,
        "set -g destroy-unattached off",
    ]

    public static var configText: String { configText(scroll: .default) }

    public static func configText(scroll: TerminalScrollSettings) -> String {
        (baseConfigLines + scroll.configLines).joined(separator: "\n") + "\n"
    }

    public static func sessionArgs(socket: String, config: String, name: String,
                                   cwd: String, command: [String], shell: String,
                                   sandbox: PaneSandbox? = nil) -> [String] {
        var a = ["-L", socket, "-f", config, "new-session", "-A", "-s", name, "-c", cwd, "--"]
        if let sandbox, !sandbox.environment.isEmpty {
            a += PaneEnvInjector.wrap(command: command, shell: shell, sandbox: sandbox)
        } else if command.isEmpty {
            a += [shell, "-l"]
        } else {
            a += [shell, "-l", "-c", "exec " + command.map(shq).joined(separator: " ")]
        }
        return a
    }

    public static func listNamesArgs(socket: String) -> [String] {
        ["-L", socket, "list-sessions", "-F", "#{session_name}"]
    }

    public static func cwdArgs(socket: String, name: String) -> [String] {
        ["-L", socket, "display-message", "-p", "-t", name, "#{pane_current_path}"]
    }

    public static func commandArgs(socket: String, name: String) -> [String] {
        ["-L", socket, "display-message", "-p", "-t", name, "#{pane_current_command}"]
    }

    public static func killArgs(socket: String, name: String) -> [String] {
        ["-L", socket, "kill-session", "-t", name]
    }

    public static func captureArgs(socket: String, name: String, startLine: Int? = nil) -> [String] {
        var a = ["-L", socket, "capture-pane", "-p", "-t", name]
        if let n = startLine, n > 0 {
            a += ["-S", "-\(n)"]
        }
        return a
    }

    public static func parseCaptureLines(_ output: String) -> [String] {
        var lines = output.components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    public static func normalizeHandle(_ raw: String, prefix: String = defaultPrefix) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if isOurs(t, prefix: prefix) { return t }
        return sessionName(t, prefix: prefix)
    }

    public static func parseNames(_ output: String, prefix: String = defaultPrefix) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { isOurs($0, prefix: prefix) }
    }

    public static func detached(all: [TmuxBackedSession], openNames: Set<String>) -> [TmuxBackedSession] {
        all.filter { !openNames.contains($0.name) }
    }

    static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - 실행 (I/O)

    public func writeConfig(scroll: TerminalScrollSettings) {
        let fm = FileManager.default
        let dir = (configPath as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Self.configText(scroll: scroll).write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            logger.error("writeConfig failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    public func applyScrollLive(_ scroll: TerminalScrollSettings) async -> Bool {
        guard let bin = tmuxBin else { return false }
        writeConfig(scroll: scroll)
        let args = TerminalScrollSettings.sourceFileArgs(socket: socket, config: configPath)
        return await runner.run(bin, args, timeout: 5).ok
    }

    public func launchArgs(name: String, cwd: String, command: [String], shell: String,
                           sandbox: PaneSandbox? = nil) -> [String] {
        Self.sessionArgs(socket: socket, config: configPath, name: name,
                         cwd: cwd, command: command, shell: shell, sandbox: sandbox)
    }

    public func listSessions() async -> [TmuxBackedSession] {
        guard let bin = tmuxBin else { return [] }
        let r = await runner.run(bin, Self.listNamesArgs(socket: socket), timeout: 5)
        guard r.ok else { return [] }
        var out: [TmuxBackedSession] = []
        for name in Self.parseNames(r.stdout, prefix: prefix) {
            let c = await runner.run(bin, Self.cwdArgs(socket: socket, name: name), timeout: 5)
            let cmd = await runner.run(bin, Self.commandArgs(socket: socket, name: name), timeout: 5)
            out.append(TmuxBackedSession(name: name, cwd: c.trimmedStdout, command: cmd.trimmedStdout))
        }
        return out
    }

    @discardableResult
    public func kill(name: String) async -> Bool {
        guard let bin = tmuxBin else { return false }
        let r = await runner.run(bin, Self.killArgs(socket: socket, name: name), timeout: 5)
        return r.ok
    }

    public func capturePane(name: String, startLine: Int? = nil) async -> [String]? {
        guard let bin = tmuxBin else { return nil }
        let r = await runner.run(bin, Self.captureArgs(socket: socket, name: name, startLine: startLine),
                                 timeout: 10)
        guard r.ok else { return nil }
        return Self.parseCaptureLines(r.stdout)
    }
}
