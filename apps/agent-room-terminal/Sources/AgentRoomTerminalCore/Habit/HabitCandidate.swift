import Foundation

/// 방 `habits/candidates.jsonl` 한 줄. stdout·stderr 본문은 남기지 않는다.
public struct HabitCandidate: Codable, Equatable, Sendable {
    public var ts: String
    public var argv: [String]
    public var exitCode: Int
    public var durationMs: Int
    public var tool: String

    public init(
        ts: String,
        argv: [String],
        exitCode: Int,
        durationMs: Int,
        tool: String
    ) {
        self.ts = ts
        self.argv = argv
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.tool = tool
    }

    public var invocation: String {
        argv.joined(separator: " ")
    }
}

public enum HabitCandidateStore {
    public static let defaultHandoffLimit = 20

    public static func append(
        in room: URL,
        argv: [String],
        exitCode: Int,
        durationMs: Int,
        tool: String,
        clock: any DaemonClock = SystemDaemonClock()
    ) throws {
        try FileManager.default.createDirectory(
            at: HabitFile.habits(in: room),
            withIntermediateDirectories: true
        )
        let candidate = HabitCandidate(
            ts: HandoffJSON.iso(clock.now()),
            argv: argv,
            exitCode: exitCode,
            durationMs: durationMs,
            tool: tool
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(candidate)
        data.append(contentsOf: "\n".utf8)
        let url = HabitFile.candidates(in: room)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer {
                // allow:silent-error-swallow — close 실패는 append 본문과 무관
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    public static func list(in room: URL) throws -> [HabitCandidate] {
        let url = HabitFile.candidates(in: room)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = HabitJSON.decoder()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
            do {
                return try decoder.decode(HabitCandidate.self, from: data)
            } catch {
                // jsonl 한 줄이 깨져도 나머지 후보를 읽는다.
                return nil
            }
        }
    }

    public static func recent(in room: URL, limit: Int = defaultHandoffLimit) throws -> [HabitCandidate] {
        Array(try list(in: room).suffix(limit))
    }

    /// 후보를 방 `habits/*.habit.json` 확정 습관으로 올린다. 이미 같은 invocation 이 있으면 건너뛴다.
    @discardableResult
    public static func promote(in room: URL, store: HabitStore) throws -> [Habit] {
        let candidates = try list(in: room)
        let existing = try store.list(in: room)
        var used = Set(existing.flatMap { $0.steps.map(\.invocation) })
        var created: [Habit] = []
        for candidate in candidates {
            let invocation = candidate.invocation
            if invocation.isEmpty || used.contains(invocation) { continue }
            let cli = candidate.argv.first ?? candidate.tool
            let command = candidate.argv.count > 1 ? candidate.argv[1] : cli
            let args = Array(candidate.argv.dropFirst(2))
            let habit = try store.create(
                in: room,
                title: invocation,
                steps: [
                    HabitStep(tool: cli, command: command, args: args),
                ],
                verify: invocation,
                createdBy: "candidate"
            )
            used.insert(invocation)
            created.append(habit)
        }
        return created
    }
}

public struct HabitListPayload: Codable, Equatable, Sendable {
    public var habits: [Habit]
    public var candidates: [HabitCandidate]

    public init(habits: [Habit], candidates: [HabitCandidate]) {
        self.habits = habits
        self.candidates = candidates
    }
}