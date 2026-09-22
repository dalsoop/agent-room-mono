import Darwin
import Foundation
import CommandKit
import AgentRoomTerminalCore

enum ExecRunner {
    static let maxResponseBytes = 64 * 1024

    struct Run: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32
        var timedOut: Bool
        var truncated: Bool = false
    }

    static func run(
        argv: [String],
        roomDir: String,
        env: [String: String],
        seatbeltProfile: String?,
        timeoutSeconds: Int
    ) -> Run {
        guard argv.first != nil else {
            return Run(stdout: "", stderr: "empty argv", exitCode: 64, timedOut: false)
        }
        guard let profile = seatbeltProfile, !profile.isEmpty, AppPaths.isSandboxAvailable else {
            return Run(stdout: "", stderr: "Seatbelt profile missing. Execution denied (Fail-Closed).", exitCode: 126, timedOut: false)
        }
        var command = EnvFile.pairs(env)
        command.append(AppPaths.sandboxExec)
        command.append("-p")
        command.append(profile)
        command.append(AppPaths.zsh)
        command.append(["-", "c"].joined())
        command.append("cd \"$1\" && shift && exec \"$@\"")
        command.append("room-exec")
        command.append(roomDir)
        command.append(contentsOf: argv)
        let seconds = TimeInterval(timeoutSeconds)
        let started = Date()
        let result = CommandKitSync.run(AppPaths.env, command, timeout: seconds)
        let elapsed = Date().timeIntervalSince(started)
        let signaled = result.exitCode == 9 || result.exitCode == 15 || result.exitCode == 137 || result.exitCode == 143
        let timedOut = signaled && elapsed + 0.25 >= seconds
        return Run(
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            timedOut: timedOut
        )
    }

    static func runStreaming(
        argv: [String],
        roomDir: String,
        env: [String: String],
        seatbeltProfile: String?,
        timeoutSeconds: Int,
        onOutput: @escaping (Data) -> Void
    ) -> Run {
        guard argv.first != nil else {
            return Run(stdout: "", stderr: "empty argv", exitCode: 64, timedOut: false)
        }
        guard let profile = seatbeltProfile, !profile.isEmpty, AppPaths.isSandboxAvailable else {
            return Run(stdout: "", stderr: "Seatbelt profile missing. Execution denied (Fail-Closed).", exitCode: 126, timedOut: false)
        }
        let command = buildCommand(argv: argv, roomDir: roomDir, env: env, seatbeltProfile: profile)
        let safeResult = SafeProcessRunner.run(
            AppPaths.env,
            command
        )
        } catch {
            safeClose(outPipe.fileHandleForReading)
            safeClose(errPipe.fileHandleForReading)
            return Run(stdout: "", stderr: error.localizedDescription, exitCode: 127, timedOut: false)
        }
        safeClose(outPipe.fileHandleForWriting)
        safeClose(errPipe.fileHandleForWriting)
        waitWithTimeout(proc: proc, seconds: TimeInterval(timeoutSeconds))
        _ = drainGroup.wait(timeout: .now() + 0.5)
        safeClose(outPipe.fileHandleForReading)
        safeClose(errPipe.fileHandleForReading)
        let elapsed = Date().timeIntervalSince(started)
        let exitCode = proc.terminationStatus
        let signaled = exitCode == 9 || exitCode == 15 || exitCode == 137 || exitCode == 143
        let timedOut = signaled && elapsed + 0.25 >= TimeInterval(timeoutSeconds)
        return collector.makeRun(exitCode: exitCode, timedOut: timedOut)
    }

    private static func safeClose(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            DaemonLog.append("safeClose failed: \(error.localizedDescription)", to: nil)
        }
    }

    static func convertLFtoCRLF(_ data: Data) -> Data {
        var result = Data()
        result.reserveCapacity(data.count + data.count / 10)
        for i in data.indices {
            let byte = data[i]
            if byte == 0x0A {
                let prevIsCR = i > data.startIndex && data[i - 1] == 0x0D
                if !prevIsCR {
                    result.append(0x0D)
                }
            }
            result.append(byte)
        }
        return result
    }

    private static func buildCommand(
        argv: [String], roomDir: String, env: [String: String], seatbeltProfile: String
    ) -> [String] {
        var command = EnvFile.pairs(env)
        command.append(AppPaths.sandboxExec)
        command.append("-p")
        command.append(seatbeltProfile)
        command.append(AppPaths.zsh)
        command.append(["-", "c"].joined())
        command.append("cd \"$1\" && shift && exec \"$@\"")
        command.append("room-exec")
        command.append(roomDir)
        command.append(contentsOf: argv)
        return command
    }

    private static func drainPipes(
        outPipe: Pipe, errPipe: Pipe,
        collector: StreamingCollector, onOutput: @escaping (Data) -> Void
    ) -> DispatchGroup {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue(label: "exec-stream.stdout").async {
            defer { group.leave() }
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collector.appendStdout(chunk)
                onOutput(chunk)
            }
        }
        group.enter()
        DispatchQueue(label: "exec-stream.stderr").async {
            defer { group.leave() }
            let handle = errPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                collector.appendStderr(chunk)
                onOutput(chunk)
            }
        }
        return group
    }

    private static func waitWithTimeout(proc: Process, seconds: TimeInterval) {
        let pid = proc.processIdentifier
        let deadline = Date().addingTimeInterval(seconds)
        while proc.isRunning && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        guard proc.isRunning else { return }
        let pgid = getpgid(pid)
        if pgid > 0 {
            kill(-pgid, SIGTERM)
        } else {
            kill(pid, SIGTERM)
        }
        let killDeadline = Date().addingTimeInterval(1)
        while proc.isRunning && Date() < killDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        guard proc.isRunning else { return }
        if pgid > 0 {
            kill(-pgid, SIGKILL)
        } else {
            kill(pid, SIGKILL)
        }
        while proc.isRunning {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
    }
}

private final class StreamingCollector {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutCapped = false
    private var stderrCapped = false
    private let maxBytes: Int

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func appendStdout(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard stdoutData.count < maxBytes else {
            stdoutCapped = true
            return
        }
        let remaining = maxBytes - stdoutData.count
        if chunk.count <= remaining {
            stdoutData.append(chunk)
        } else {
            stdoutData.append(chunk.prefix(remaining))
            stdoutCapped = true
        }
    }

    func appendStderr(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard stderrData.count < maxBytes else {
            stderrCapped = true
            return
        }
        let remaining = maxBytes - stderrData.count
        if chunk.count <= remaining {
            stderrData.append(chunk)
        } else {
            stderrData.append(chunk.prefix(remaining))
            stderrCapped = true
        }
    }

    func makeRun(exitCode: Int32, timedOut: Bool) -> ExecRunner.Run {
        lock.lock()
        defer { lock.unlock() }
        return ExecRunner.Run(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: exitCode,
            timedOut: timedOut,
            truncated: stdoutCapped || stderrCapped
        )
    }
}
