import Foundation
import RoomKit

/// 원장에 남기는 빈병 증류물 — predecessor·budget·tool + 함정·결정·남은 일.
/// 옛 JSON 은 세 칸이 없어도 빈 배열로 읽는다.
public struct HandoffDigest: Codable, Equatable, Sendable {
    public var id: String
    public var predecessor: String?
    public var budget: BudgetState
    public var tool: String
    public var pitfalls: [String]
    public var decisions: [String]
    public var remaining: [String]

    public init(
        id: String,
        predecessor: String?,
        budget: BudgetState,
        tool: String,
        pitfalls: [String] = [],
        decisions: [String] = [],
        remaining: [String] = []
    ) {
        self.id = id
        self.predecessor = predecessor
        self.budget = budget
        self.tool = tool
        self.pitfalls = pitfalls
        self.decisions = decisions
        self.remaining = remaining
    }

    enum CodingKeys: String, CodingKey {
        case id, predecessor, budget, tool, pitfalls, decisions, remaining
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        predecessor = try container.decodeIfPresent(String.self, forKey: .predecessor)
        budget = try container.decode(BudgetState.self, forKey: .budget)
        tool = try container.decode(String.self, forKey: .tool)
        pitfalls = try container.decodeIfPresent([String].self, forKey: .pitfalls) ?? []
        decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
        remaining = try container.decodeIfPresent([String].self, forKey: .remaining) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(predecessor, forKey: .predecessor)
        try container.encode(budget, forKey: .budget)
        try container.encode(tool, forKey: .tool)
        try container.encode(pitfalls, forKey: .pitfalls)
        try container.encode(decisions, forKey: .decisions)
        try container.encode(remaining, forKey: .remaining)
    }

    /// CLI `handoff --note/--pitfall/--decision/--remaining` 반복 인자 파서.
    /// 순수 함수 — 프로세스·파일에 손대지 않는다. `--flag value` 와 `--flag=value` 를 받는다.
    public static func apply(arguments: [String]) -> HandoffDigest {
        let parsed = HandoffCLIArguments.parse(arguments)
        return HandoffDigest(
            id: "",
            predecessor: nil,
            budget: HandoffDigest.emptyBudget,
            tool: "",
            pitfalls: parsed.pitfalls,
            decisions: parsed.decisions,
            remaining: parsed.remaining
        )
    }

    public func applying(arguments: [String]) -> HandoffDigest {
        let parsed = HandoffCLIArguments.parse(arguments)
        var copy = self
        copy.pitfalls.append(contentsOf: parsed.pitfalls)
        copy.decisions.append(contentsOf: parsed.decisions)
        copy.remaining.append(contentsOf: parsed.remaining)
        return copy
    }

    static let emptyBudget = BudgetState(
        window: 0,
        trigger: 0,
        initialInput: 0,
        reservedOutput: 0,
        usable: 0,
        used: nil,
        handoffAt: 0,
        elapsedMinutes: nil,
        estimatedWorkMinutes: nil,
        state: .unknown
    )
}

/// `handoff` CLI 반복 플래그. `HandoffDigest.apply` 가 소비한다.
public struct HandoffCLIArguments: Equatable, Sendable {
    public var note: String?
    public var pitfalls: [String]
    public var decisions: [String]
    public var remaining: [String]

    public init(
        note: String? = nil,
        pitfalls: [String] = [],
        decisions: [String] = [],
        remaining: [String] = []
    ) {
        self.note = note
        self.pitfalls = pitfalls
        self.decisions = decisions
        self.remaining = remaining
    }

    public static func parse(_ arguments: [String]) -> HandoffCLIArguments {
        var note: String?
        var pitfalls: [String] = []
        var decisions: [String] = []
        var remaining: [String] = []
        var index = 0
        while index < arguments.count {
            let item = arguments[index]
            if item == "--" { break }
            guard let (flag, inline) = splitFlag(item) else {
                index += 1
                continue
            }
            let taken = takeValue(inline: inline, arguments: arguments, at: index)
            index = taken.next
            guard let value = taken.value else { continue }
            switch flag {
            case "--note":
                if note == nil { note = value }
            case "--pitfall":
                pitfalls.append(value)
            case "--decision":
                decisions.append(value)
            case "--remaining":
                remaining.append(value)
            default:
                break
            }
        }
        return HandoffCLIArguments(
            note: note,
            pitfalls: pitfalls,
            decisions: decisions,
            remaining: remaining
        )
    }

    /// `--flag=값` 이면 inline, 아니면 다음 인자(대시로 시작하지 않는 것)를 값으로 쓴다.
    private static func takeValue(
        inline: String?,
        arguments: [String],
        at index: Int
    ) -> (value: String?, next: Int) {
        if let inline { return (inline, index + 1) }
        let nextIndex = index + 1
        guard nextIndex < arguments.count, !arguments[nextIndex].hasPrefix("-") else {
            return (nil, index + 1)
        }
        return (arguments[nextIndex], index + 2)
    }

    private static func splitFlag(_ item: String) -> (String, String?)? {
        guard item.hasPrefix("--") else { return nil }
        if let eq = item.firstIndex(of: "=") {
            return (String(item[..<eq]), String(item[item.index(after: eq)...]))
        }
        return (item, nil)
    }
}

/// 원장 handover 상태. `simulating|passed|failed` 만 유효 — `escalated` 는 failed + 빈병 note.
public enum HandoffSimulationLedgerState {
    public static let passed = "passed"
    public static let failed = "failed"

    public static func fromSimulation(_ state: String) -> String {
        if state == passed { return passed }
        return failed
    }

    public static func escalationNote(handoffID: String) -> String {
        "escalated: maxBottleSwaps exceeded for \(handoffID); recorded as failed"
    }
}
