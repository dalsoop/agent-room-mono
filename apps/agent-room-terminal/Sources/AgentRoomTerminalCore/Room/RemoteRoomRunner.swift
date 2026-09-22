import Foundation
import CommandKit

public struct RemoteRoomExecutionResult: Sendable, Equatable, Codable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum RemoteRoomCommandBuilder {
    public static func shellQuote(_ arg: String) -> String {
        if arg.isEmpty { return "''" }
        let isSafe = arg.allSatisfy { c in
            c.isLetter || c.isNumber
                || c == "_" || c == "." || c == "/" || c == "-"
                || c == "=" || c == ":" || c == "," || c == "@"
        }
        if isSafe { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func parseHost(
        from arguments: [String]
    ) -> (host: String?, remainingArgs: [String]) {
        let preDash: [String]
        let postDash: [String]
        if let dashIndex = arguments.firstIndex(of: "--") {
            preDash = Array(arguments[..<dashIndex])
            postDash = Array(arguments[dashIndex...])
        } else {
            preDash = arguments
            postDash = []
        }
        return splitHost(preDash: preDash, postDash: postDash)
    }

    public static func buildRemoteCommandLine(
        binary: String = "agent-room-terminal",
        subcommand: String = "room",
        args: [String]
    ) -> String {
        let fullArgs = [binary, subcommand] + args
        return fullArgs.map(shellQuote).joined(separator: " ")
    }

    private static func splitHost(
        preDash: [String],
        postDash: [String]
    ) -> (host: String?, remainingArgs: [String]) {
        var host: String?
        var remainingPreDash: [String] = []
        var skipNext = false
        for (idx, arg) in preDash.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }
            if arg == "--host" {
                if idx + 1 < preDash.count {
                    host = preDash[idx + 1]
                    skipNext = true
                }
            } else {
                remainingPreDash.append(arg)
            }
        }
        return (host, remainingPreDash + postDash)
    }
}

public protocol RemoteRoomRunning: Sendable {
    func runRemote(
        host: String,
        remoteCommandLine: String,
        timeout: TimeInterval?
    ) async throws -> RemoteRoomExecutionResult

    func runRemoteSync(
        host: String,
        remoteCommandLine: String,
        timeout: TimeInterval?
    ) throws -> RemoteRoomExecutionResult
}

public struct SSHRemoteRoomRunner: RemoteRoomRunning {
    public static let sshExecutable = "/usr/bin/ssh"
    public var connectTimeoutSeconds: Int

    public init(connectTimeoutSeconds: Int = 10) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }

    public static func buildSSHArguments(
        host: String,
        remoteCommandLine: String,
        connectTimeout: Int = 10
    ) -> (executable: String, arguments: [String]) {
        var sshArgs = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(connectTimeout)",
        ]
        var targetHost = host
        if let colon = targetHost.lastIndex(of: ":") {
            let portStr = String(targetHost[targetHost.index(after: colon)...])
            if let port = Int(portStr), !portStr.isEmpty {
                sshArgs += ["-p", String(port)]
                targetHost = String(targetHost[..<colon])
            }
        }
        sshArgs.append(targetHost)
        sshArgs.append(remoteCommandLine)
        return (sshExecutable, sshArgs)
    }

    public func runRemote(
        host: String,
        remoteCommandLine: String,
        timeout: TimeInterval? = nil
    ) async throws -> RemoteRoomExecutionResult {
        let pair = Self.buildSSHArguments(
            host: host,
            remoteCommandLine: remoteCommandLine,
            connectTimeout: connectTimeoutSeconds
        )
        let result = await ProcessCommandRunner().run(pair.executable, pair.arguments, timeout: timeout)
        return RemoteRoomExecutionResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    public func runRemoteSync(
        host: String,
        remoteCommandLine: String,
        timeout: TimeInterval? = nil
    ) throws -> RemoteRoomExecutionResult {
        let pair = Self.buildSSHArguments(
            host: host,
            remoteCommandLine: remoteCommandLine,
            connectTimeout: connectTimeoutSeconds
        )
        let result = CommandKitSync.run(pair.executable, pair.arguments, timeout: timeout)
        return RemoteRoomExecutionResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}


