import Foundation
import CommandKit

/// 소유 앱 `capabilities --json` 의 해당 명령 `dryRun: true` 계약.
public protocol CapabilityLookup: Sendable {
    func hasDryRun(tool: String, command: String) -> Bool
}

public struct ExecRunResult: Sendable, Equatable {
    public var exit: Int32
    public var stdout: String
    public var stderr: String

    public init(exit: Int32, stdout: String, stderr: String) {
        self.exit = exit
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combined: String {
        stdout + stderr
    }
}

/// 데몬 `exec` / `closeSession`. dry-run 계약이 없는 명령은 호출하지 않는다.
public protocol ExecRunning: Sendable {
    func exec(roomDir: String, sessionID: String?, argv: [String]) throws -> ExecRunResult
    func closeSession(sessionID: String) throws
}

/// 원장 `handover --state`. `LedgerQueue.submit` 으로만 나간다.
public protocol LedgerHandoverSubmitting: Sendable {
    func submitHandover(
        planID: String,
        roomID: String,
        state: String,
        by authority: LedgerAuthority
    ) async -> LedgerReply
}

extension LedgerQueue: LedgerHandoverSubmitting {
    public func submitHandover(
        planID: String,
        roomID: String,
        state: String,
        by authority: LedgerAuthority
    ) async -> LedgerReply {
        await submit(.handover(planID: planID, roomID: roomID, state: state), by: authority)
    }
}

public struct NoopLedgerHandover: LedgerHandoverSubmitting {
    public init() {}

    public func submitHandover(
        planID: String,
        roomID: String,
        state: String,
        by authority: LedgerAuthority
    ) async -> LedgerReply {
        .success(#"{"ok":true,"kind":"handover"}"#)
    }
}

/// T8 `HandoffService.amend` 호출 지점. 보강 내용은 세션 몫.
public protocol HandoffAmending: Sendable {
    func amend(room: URL, handoffID: String) throws
}

public protocol WikiPublishing: Sendable {
    func run(argv: [String], environment: [String: String]) throws -> ExecRunResult
}

public struct MapCapabilityLookup: CapabilityLookup {
    public var dryRun: [String: Set<String>]

    public init(dryRun: [String: Set<String>] = [:]) {
        self.dryRun = dryRun
    }

    public func hasDryRun(tool: String, command: String) -> Bool {
        guard let names = dryRun[tool] else { return false }
        return names.contains(command)
    }
}

/// `capabilities --json` 에서 명령별 `dryRun` 을 읽는다. 필드가 없으면 실행하지 않는다.
public struct JSONCapabilityLookup: CapabilityLookup, Sendable {
    public var documents: [String: Data]

    public init(documents: [String: Data] = [:]) {
        self.documents = documents
    }

    public func hasDryRun(tool: String, command: String) -> Bool {
        guard let data = documents[tool] else { return false }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            return false
        }
        return Self.commands(in: root).contains { entry in
            entry.name == command && entry.dryRun
        }
    }

    private struct CommandFlag {
        var name: String
        var dryRun: Bool
    }

    private static func commands(in root: Any) -> [CommandFlag] {
        let tree: Any
        if let object = root as? [String: Any], let result = object["result"] {
            tree = result
        } else {
            tree = root
        }
        guard let object = tree as? [String: Any] else { return [] }
        guard let list = object["commands"] as? [Any] else { return [] }
        return list.compactMap { item in
            guard let entry = item as? [String: Any] else { return nil }
            guard let name = entry["name"] as? String else { return nil }
            let dry = (entry["dryRun"] as? Bool) ?? false
            return CommandFlag(name: name, dryRun: dry)
        }
    }
}

public struct DaemonClientExec: ExecRunning {
    public var client: DaemonClient

    public init(client: DaemonClient) {
        self.client = client
    }

    public func exec(roomDir: String, sessionID: String?, argv: [String]) throws -> ExecRunResult {
        let response = try client.send(.exec(sessionID: sessionID, roomDir: roomDir, argv: argv))
        guard response.ok else {
            throw HabitError.execFailed(response.error ?? "unknown")
        }
        return ExecRunResult(
            exit: Int32(response.result?["exitCode"]?.int ?? 1),
            stdout: response.result?["stdout"]?.string ?? "",
            stderr: response.result?["stderr"]?.string ?? ""
        )
    }

    public func closeSession(sessionID: String) throws {
        let response = try client.send(.closeSession(sessionID: sessionID))
        guard response.ok else {
            throw HabitError.closeFailed(response.error ?? "unknown")
        }
    }
}

public struct WikiCommandKitPublisher: WikiPublishing {
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(argv: [String], environment: [String: String]) throws -> ExecRunResult {
        var merged = self.environment
        for (key, value) in environment {
            merged[key] = value
        }
        guard let first = argv.first else {
            return ExecRunResult(exit: 0, stdout: "", stderr: "")
        }
        let path = first.contains("/") ? first : (BinaryLocator.find(first, path: merged["PATH"] ?? "") ?? first)
        let output = CommandKitSync.run(path, Array(argv.dropFirst()), timeout: 30)
        return ExecRunResult(exit: output.exitCode, stdout: output.stdout, stderr: output.stderr)
    }
}
