import Foundation
import InteropKit
import CommandKit
import os
import AgentRoomTerminalCore

enum CLIExit {
    static let ok: Int32 = 0
    static let fail: Int32 = 1
    static let checkDeny: Int32 = 2
    static let usage: Int32 = 64
}

enum CLIIO {
    static func printOK(_ result: some Codable) {
        do {
            let data = try Envelope.ok(result)
            writeStdout(data)
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func printOKObject(_ result: Any) {
        do {
            let data = try Envelope.okObject(result)
            writeStdout(data)
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func fail(_ message: String, code: Int32 = CLIExit.fail) -> Never {
        do {
            let data = try Envelope.fail(message)
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        exit(code)
    }

    static func writeStdout(_ data: Data) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func printLine(_ text: String) {
        print(text) // allow:debug — CLI human stdout
    }
}

enum CLIArgs {
    static func has(_ flag: String, in args: [String]) -> Bool {
        args.contains(flag)
    }

    static func value(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    static func takeExecute(_ args: inout [String]) -> Bool {
        let found = args.contains("--execute")
        args.removeAll { $0 == "--execute" }
        return found
    }

    static func takeJSON(_ args: inout [String]) -> Bool {
        let found = args.contains("--json")
        args.removeAll { $0 == "--json" }
        return found
    }

    static func takeFlag(_ flag: String, from args: inout [String]) -> Bool {
        let found = args.contains(flag)
        args.removeAll { $0 == flag }
        return found
    }

    static func afterDashDash(_ args: [String]) -> [String]? {
        guard let index = args.firstIndex(of: "--") else { return nil }
        return Array(args[(index + 1)...])
    }

    static func dropFlags(_ args: [String], flags: Set<String>, valueFlags: Set<String>) -> [String] {
        var out: [String] = []
        var index = 0
        while index < args.count {
            let item = args[index]
            if item == "--" {
                out.append(contentsOf: args[index...])
                break
            }
            if flags.contains(item) {
                index += 1
                continue
            }
            if valueFlags.contains(item) {
                index += 2
                continue
            }
            out.append(item)
            index += 1
        }
        return out
    }
}

enum CLIAsync {
    static func run(_ body: @escaping @Sendable () async throws -> Void) {
        let box = OSAllocatedUnfairLock<Error?>(initialState: nil)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await body()
            } catch {
                box.withLock { $0 = error }
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = box.withLock({ $0 }) {
            CLIIO.fail(error.localizedDescription)
        }
    }
}

enum CLIJSON {
    static func object(from value: JSONValue) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func unwrap(_ any: Any) -> Any {
        guard let dict = any as? [String: Any] else { return any }
        if let result = dict["result"] { return unwrap(result) }
        if let payload = dict["payload"] { return unwrap(payload) }
        return dict
    }
}

enum CLIProcess {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) -> (exit: Int32, stdout: String, stderr: String) {
        // CommandKitSync 는 청크 드레인을 갖고 있어 300KB+ 원장 목록에서도 교착하지 않는다.
        // 호출자가 준 env 가 현재 프로세스와 같으면 상속만 쓰고, 다를 때만 env(1) 로 덮는다.
        let result: CommandResult
        if environment == ProcessInfo.processInfo.environment {
            result = CommandKitSync.run(executable, arguments, timeout: 30)
        } else {
            let pairs = environment.map { key, value in
                "\(key)=\(value.replacingOccurrences(of: "\0", with: ""))"
            }
            result = CommandKitSync.run(
                "/usr/bin/env",
                pairs + [executable] + arguments,
                timeout: 30
            )
        }
        return (result.exitCode, result.stdout, result.stderr)
    }
}

enum DryRunPlan {
    static func object(command: String, roomID: String?, steps: [String]) -> [String: Any] {
        var result: [String: Any] = [
            "dryRun": true,
            "command": command,
            "steps": steps,
            "executed": false,
        ]
        if let roomID {
            result["roomID"] = roomID
        }
        return result
    }
}
