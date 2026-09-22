import Foundation
import os
@testable import AgentRoomTerminalCore

enum HabitTestIDs {
    static let plan = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    static let room = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    static let handoff = "handoff-1"
    static let session = "pred-session"
}

final class OrderLog: Sendable {
    private struct State: Sendable {
        var events: [String] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var events: [String] { lock.withLock { $0.events } }

    func append(_ event: String) {
        lock.withLock { $0.events.append(event) }
    }
}

final class SpyExec: ExecRunning, Sendable {
    private struct State: Sendable {
        var calls: [[String]] = []
        var closes: [String] = []
        var stdout = "OK"
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    let log: OrderLog

    init(log: OrderLog) {
        self.log = log
    }

    var calls: [[String]] { lock.withLock { $0.calls } }
    var closes: [String] { lock.withLock { $0.closes } }

    func exec(roomDir: String, sessionID: String?, argv: [String]) throws -> ExecRunResult {
        let stdout = lock.withLock { state -> String in
            state.calls.append(argv)
            return state.stdout
        }
        log.append("exec")
        return ExecRunResult(exit: 0, stdout: stdout, stderr: "")
    }

    func closeSession(sessionID: String) throws {
        lock.withLock { $0.closes.append(sessionID) }
        log.append("close")
    }
}

final class SpyLedger: LedgerHandoverSubmitting, Sendable {
    private struct State: Sendable {
        var states: [String] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    let log: OrderLog

    init(log: OrderLog) {
        self.log = log
    }

    var states: [String] { lock.withLock { $0.states } }

    func submitHandover(
        planID: String,
        roomID: String,
        state: String,
        by authority: LedgerAuthority
    ) async -> LedgerReply {
        lock.withLock { $0.states.append(state) }
        log.append("handover:\(state)")
        return .success("{}")
    }
}

final class SpyAmend: HandoffAmending, Sendable {
    private struct State: Sendable {
        var ids: [String] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var ids: [String] { lock.withLock { $0.ids } }

    func amend(room: URL, handoffID: String) throws {
        lock.withLock { $0.ids.append(handoffID) }
    }
}

final class SpyWiki: WikiPublishing, Sendable {
    private struct State: Sendable {
        var argvLog: [[String]] = []
        var environments: [[String: String]] = []
        var stdoutQueue: [String]
        var exitCode: Int32 = 0
    }

    private let lock: OSAllocatedUnfairLock<State>

    init(stdoutQueue: [String] = ["cand-1", "rcpt-1"]) {
        self.lock = OSAllocatedUnfairLock(initialState: State(stdoutQueue: stdoutQueue))
    }

    var argvLog: [[String]] { lock.withLock { $0.argvLog } }
    var environments: [[String: String]] { lock.withLock { $0.environments } }

    func run(argv: [String], environment: [String: String]) throws -> ExecRunResult {
        lock.withLock { state in
            state.argvLog.append(argv)
            state.environments.append(environment)
            let text = state.stdoutQueue.isEmpty ? "" : state.stdoutQueue.removeFirst()
            return ExecRunResult(exit: state.exitCode, stdout: text + "\n", stderr: "")
        }
    }
}

enum HabitRoomFixture {
    static func makeRoom(
        verdict: String = "gujo-catalog-manager doctor",
        snapshot: String = "gujo-catalog-manager doctor\nhealthy\n",
        termLog: String = "gujo-catalog-manager doctor\nhealthy\n",
        verdictOutput: String = "healthy",
        candidates: [HabitCandidate] = []
    ) throws -> URL {
        let fm = FileManager.default
        let room = fm.temporaryDirectory.appendingPathComponent(
            "habit-room-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: room, withIntermediateDirectories: true)
        for name in ["habits", "handoff", "state/notes"] {
            try fm.createDirectory(
                at: room.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let json = """
        {"id":"\(HabitTestIDs.room)","task":"판매 카탈로그를 운영한다","verdict":"\(verdict)"}
        """
        try Data(json.utf8).write(to: room.appendingPathComponent("ROOM.json"))
        try Data("AGENT_WIKI_WORLD=tenant-gujo\n".utf8).write(
            to: room.appendingPathComponent("env")
        )
        let bottle = HabitHandoffSnapshot(
            id: HabitTestIDs.handoff,
            sessionID: HabitTestIDs.session,
            planID: HabitTestIDs.plan,
            roomID: HabitTestIDs.room,
            snapshot: snapshot,
            verdictOutput: verdictOutput,
            habitCandidates: candidates
        )
        let data = try HabitJSON.encoder().encode(bottle)
        try data.write(to: HabitFile.handoff(in: room, id: HabitTestIDs.handoff))
        try Data(termLog.utf8).write(to: HabitFile.termLog(in: room))
        return room
    }

    static func authority() -> LedgerAuthority {
        .commandRoom(sessionID: "successor", seatedRoomID: HabitTestIDs.room)
    }

    static func linkTool(in room: URL, name: String) throws {
        let fm = FileManager.default
        let bin = room.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let stub = room.appendingPathComponent(".\(name)-stub")
        try Data().write(to: stub)
        let link = bin.appendingPathComponent(name)
        if fm.fileExists(atPath: link.path) {
            try fm.removeItem(at: link)
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: stub)
    }

    static func step(
        tool: String,
        command: String,
        args: [String] = [],
        dryRunSupported: Bool = false,
        expectedPattern: String? = nil
    ) -> HabitStep {
        HabitStep(
            tool: tool,
            command: command,
            args: args,
            dryRunSupported: dryRunSupported,
            expectedPattern: expectedPattern
        )
    }
}
