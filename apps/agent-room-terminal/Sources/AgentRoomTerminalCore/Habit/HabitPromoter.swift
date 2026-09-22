import Foundation

/// 안정된 습관을 테넌트 world 에 발행한 뒤 공유 world 로 자동 승격한다.
public struct HabitPromoter: Sendable {
    public var store: HabitStore
    public var wiki: any WikiPublishing
    public var tuning: HabitTuning
    public var environment: [String: String]

    public init(
        store: HabitStore = HabitStore(),
        wiki: any WikiPublishing,
        tuning: HabitTuning = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.store = store
        self.wiki = wiki
        self.tuning = tuning
        self.environment = environment
    }

    @discardableResult
    public func promote(room: URL, number: Int) throws -> Habit {
        var habit = try store.load(number: number, in: room)
        let eligible = habit.successCount >= tuning.promoteMinSuccess
            && habit.failureCount == tuning.promoteMaxFailure
        guard eligible else { return habit }
        let context = try RoomHabitContext.load(room: room)
        var env = environment
        if let world = try RoomEnvReader.value("AGENT_WIKI_WORLD", in: room) {
            env["AGENT_WIKI_WORLD"] = world
        }
        let candidate = try publishCandidate(task: context.task, title: habit.title, env: env)
        habit.wikiCandidate = candidate
        try store.save(habit, in: room)
        let receipt = try publishPromotion(id: candidate, env: env)
        habit.wikiReceipt = receipt
        try store.save(habit, in: room)
        return habit
    }

    private func publishCandidate(
        task: String,
        title: String,
        env: [String: String]
    ) throws -> String {
        let argv = [HabitFile.wikiCLI, "task", "knowledge-candidate", task, title]
        return try requireID(wiki.run(argv: argv, environment: env))
    }

    private func publishPromotion(id: String, env: [String: String]) throws -> String {
        let argv = [
            HabitFile.wikiCLI, "promotion", "publish", id,
            "--to", "gujo", "--confirm",
        ]
        return try requireID(wiki.run(argv: argv, environment: env))
    }

    private func requireID(_ output: ExecRunResult) throws -> String {
        if output.exit != 0 {
            throw HabitError.wikiFailed(exit: output.exit, stderr: output.stderr)
        }
        return try WikiObjectID.parse(output.stdout)
    }
}

enum WikiObjectID {
    static func parse(_ stdout: String) throws -> String {
        if let fromJSON = idFromJSON(stdout) {
            return fromJSON
        }
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: true)
        if let last = lines.last {
            let token = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        throw HabitError.wikiIDMissing
    }

    private static func idFromJSON(_ stdout: String) -> String? {
        guard let start = stdout.firstIndex(of: "{") else { return nil }
        let blob = String(stdout[start...])
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: Data(blob.utf8))
        } catch {
            return nil
        }
        guard let object = raw as? [String: Any] else { return nil }
        if let id = object["id"] as? String, !id.isEmpty { return id }
        if let result = object["result"] as? String, !result.isEmpty { return result }
        if let nested = object["result"] as? [String: Any],
           let id = nested["id"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }
}
