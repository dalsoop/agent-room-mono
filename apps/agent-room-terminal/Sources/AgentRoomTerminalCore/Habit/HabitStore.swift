import Foundation

/// 방 `habits/` 파일과 INDEX.md. successCount 갱신은 `recordOutcome` 으로만.
public struct HabitStore: Sendable {
    public var clock: any DaemonClock
    public var tuning: HabitTuning

    public init(clock: any DaemonClock = SystemDaemonClock(), tuning: HabitTuning = .default) {
        self.clock = clock
        self.tuning = tuning
    }

    public func create(
        in room: URL,
        title: String,
        steps: [HabitStep],
        verify: String,
        createdBy: String
    ) throws -> Habit {
        try ensureLayout(in: room)
        let existing = try list(in: room)
        let number = (existing.map(\.number).max() ?? 0) + 1
        let slug = uniqueSlug(HabitFile.slug(from: title), used: Set(existing.map(\.slug)))
        let habit = Habit(
            number: number,
            slug: slug,
            title: title,
            steps: steps,
            verify: verify,
            createdBy: createdBy
        )
        try save(habit, in: room)
        return habit
    }

    public func save(_ habit: Habit, in room: URL) throws {
        try ensureLayout(in: room)
        try removeFiles(for: habit.number, in: room)
        let url = HabitFile.habitURL(in: room, number: habit.number, slug: habit.slug)
        let data = try HabitJSON.encoder().encode(habit)
        try data.write(to: url, options: .atomic)
        try rewriteIndex(in: room)
    }

    public func load(number: Int, in room: URL) throws -> Habit {
        guard let habit = try list(in: room).first(where: { $0.number == number }) else {
            throw HabitError.habitMissing(number)
        }
        return habit
    }

    public func list(in room: URL) throws -> [Habit] {
        let dir = HabitFile.habits(in: room)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        var habits: [Habit] = []
        for name in names where name.hasSuffix(HabitFile.suffix) {
            habits.append(try readFile(dir.appendingPathComponent(name)))
        }
        return habits.sorted { $0.number < $1.number }
    }

    public func recent(in room: URL, limit: Int? = nil) throws -> [Habit] {
        let cap = limit ?? tuning.recentCount
        return Array(try list(in: room).reversed().prefix(cap))
    }

    public func recordOutcome(number: Int, success: Bool, in room: URL) throws -> Habit {
        var habit = try load(number: number, in: room)
        if success {
            habit.successCount += 1
        } else {
            habit.failureCount += 1
        }
        habit.lastRunAt = clock.now()
        try save(habit, in: room)
        return habit
    }

    public func rewriteIndex(in room: URL) throws {
        try ensureLayout(in: room)
        let habits = try list(in: room)
        let text = HabitIndex.render(habits: habits, lineCap: tuning.indexLineCap)
        try Data(text.utf8).write(to: HabitFile.index(in: room), options: .atomic)
    }

    private func ensureLayout(in room: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: HabitFile.habits(in: room), withIntermediateDirectories: true)
        try fm.createDirectory(at: HabitFile.notes(in: room), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: room.appendingPathComponent(HabitFile.handoffDir, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func readFile(_ url: URL) throws -> Habit {
        var habit = try HabitJSON.decoder().decode(Habit.self, from: try Data(contentsOf: url))
        let stem = url.lastPathComponent.replacingOccurrences(of: HabitFile.suffix, with: "")
        let parts = stem.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        habit.number = Int(parts.first.map(String.init) ?? "") ?? 0
        habit.slug = parts.count > 1 ? String(parts[1]) : "habit"
        return habit
    }

    private func removeFiles(for number: Int, in room: URL) throws {
        let dir = HabitFile.habits(in: room)
        let prefix = HabitFile.padded(number) + "-"
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(HabitFile.suffix) {
            try fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func uniqueSlug(_ base: String, used: Set<String>) -> String {
        if !used.contains(base) { return base }
        var index = 2
        while used.contains("\(base)-\(index)") {
            index += 1
        }
        return "\(base)-\(index)"
    }
}

enum HabitIndex {
    static func render(habits: [Habit], lineCap: Int) -> String {
        let lines = habits.map(line(for:))
        if lines.count <= lineCap {
            return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        }
        let kept = lineCap - 1
        let head = Array(lines.prefix(kept))
        let extra = lines.count - kept
        let overflow = "\(HabitFile.overflowPrefix)\(extra)\(HabitFile.overflowSuffix)"
        return (head + [overflow]).joined(separator: "\n") + "\n"
    }

    static func line(for habit: Habit) -> String {
        let number = HabitFile.padded(habit.number)
        let text = "- \(number) \(habit.title) (성공 \(habit.successCount) / 실패 \(habit.failureCount))"
        return text
    }
}
