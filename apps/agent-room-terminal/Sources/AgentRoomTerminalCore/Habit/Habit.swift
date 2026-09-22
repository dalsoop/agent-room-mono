import Foundation

/// 방 폴더 `habits/<번호>-<slug>.habit.json` 한 건. 번호·slug 는 파일명에서 온다.
public struct Habit: Equatable, Sendable {
    public var number: Int
    public var slug: String
    public var title: String
    public var steps: [HabitStep]
    public var verify: String
    public var createdBy: String
    public var successCount: Int
    public var failureCount: Int
    public var lastRunAt: Date?
    public var wikiCandidate: String?
    public var wikiReceipt: String?

    public init(
        number: Int,
        slug: String,
        title: String,
        steps: [HabitStep],
        verify: String,
        createdBy: String,
        successCount: Int = 0,
        failureCount: Int = 0,
        lastRunAt: Date? = nil,
        wikiCandidate: String? = nil,
        wikiReceipt: String? = nil
    ) {
        self.number = number
        self.slug = slug
        self.title = title
        self.steps = steps
        self.verify = verify
        self.createdBy = createdBy
        self.successCount = successCount
        self.failureCount = failureCount
        self.lastRunAt = lastRunAt
        self.wikiCandidate = wikiCandidate
        self.wikiReceipt = wikiReceipt
    }
}

public struct HabitStep: Codable, Equatable, Sendable {
    public var tool: String
    public var command: String
    public var args: [String]
    public var dryRunSupported: Bool
    public var expectedPattern: String?

    public init(
        tool: String,
        command: String,
        args: [String] = [],
        dryRunSupported: Bool = false,
        expectedPattern: String? = nil
    ) {
        self.tool = tool
        self.command = command
        self.args = args
        self.dryRunSupported = dryRunSupported
        self.expectedPattern = expectedPattern
    }

    public var invocation: String {
        ([tool, command] + args).joined(separator: " ")
    }
}

extension Habit: Codable {
    enum CodingKeys: String, CodingKey {
        case title, steps, verify, createdBy, successCount, failureCount
        case lastRunAt, wikiCandidate, wikiReceipt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = 0
        slug = ""
        title = try container.decode(String.self, forKey: .title)
        steps = try container.decode([HabitStep].self, forKey: .steps)
        verify = try container.decode(String.self, forKey: .verify)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        successCount = try container.decode(Int.self, forKey: .successCount)
        failureCount = try container.decode(Int.self, forKey: .failureCount)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        wikiCandidate = try container.decodeIfPresent(String.self, forKey: .wikiCandidate)
        wikiReceipt = try container.decodeIfPresent(String.self, forKey: .wikiReceipt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(steps, forKey: .steps)
        try container.encode(verify, forKey: .verify)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(successCount, forKey: .successCount)
        try container.encode(failureCount, forKey: .failureCount)
        try container.encodeIfPresent(lastRunAt, forKey: .lastRunAt)
        try container.encodeIfPresent(wikiCandidate, forKey: .wikiCandidate)
        try container.encodeIfPresent(wikiReceipt, forKey: .wikiReceipt)
    }
}

public enum SimulationMode: String, Equatable, Sendable {
    case executed
    case compared
    case skipped
}

public struct SimulationStepResult: Equatable, Sendable {
    public var habit: String
    public var step: Int
    public var mode: SimulationMode
    public var ok: Bool
    public var reason: String

    public init(habit: String, step: Int, mode: SimulationMode, ok: Bool, reason: String) {
        self.habit = habit
        self.step = step
        self.mode = mode
        self.ok = ok
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.reason = ok ? "ok" : "failed"
        } else {
            self.reason = trimmed
        }
    }
}

public struct SimulationVerdict: Equatable, Sendable {
    public var passed: Bool
    public var steps: [SimulationStepResult]
    public var verdictMatched: Bool
    public var reason: String

    public init(
        passed: Bool,
        steps: [SimulationStepResult],
        verdictMatched: Bool,
        reason: String = ""
    ) {
        self.passed = passed
        self.steps = steps
        self.verdictMatched = verdictMatched
        self.reason = reason
    }
}

public struct HabitTuning: Equatable, Sendable {
    public var recentCount: Int
    public var maxBottleSwaps: Int
    public var promoteMinSuccess: Int
    public var promoteMaxFailure: Int
    public var indexLineCap: Int

    public init(
        recentCount: Int = 3,
        maxBottleSwaps: Int = 2,
        promoteMinSuccess: Int = 5,
        promoteMaxFailure: Int = 0,
        indexLineCap: Int = 20
    ) {
        self.recentCount = recentCount
        self.maxBottleSwaps = maxBottleSwaps
        self.promoteMinSuccess = promoteMinSuccess
        self.promoteMaxFailure = promoteMaxFailure
        self.indexLineCap = indexLineCap
    }

    public static let `default` = HabitTuning()
}

public enum HabitError: Error, Equatable, LocalizedError {
    case habitMissing(Int)
    case handoffMissing(String)
    case roomContextMissing
    case wikiFailed(exit: Int32, stderr: String)
    case wikiIDMissing
    case execFailed(String)
    case closeFailed(String)
    case handoverFailed

    public var errorDescription: String? {
        switch self {
        case .habitMissing(let number):
            return "habit \(HabitFile.padded(number)) is missing"
        case .handoffMissing(let id):
            return "handoff \(id) is missing"
        case .roomContextMissing:
            return "ROOM.json is missing task or verdict"
        case .wikiFailed(let exit, let stderr):
            return "agent-wiki failed (\(exit)): \(stderr)"
        case .wikiIDMissing:
            return "agent-wiki did not print an object id"
        case .execFailed(let message):
            return "daemon exec failed: \(message)"
        case .closeFailed(let message):
            return "daemon closeSession failed: \(message)"
        case .handoverFailed:
            return "ledger handover was not accepted"
        }
    }
}
