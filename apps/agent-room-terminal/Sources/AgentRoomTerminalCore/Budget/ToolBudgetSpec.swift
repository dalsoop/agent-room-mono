import Foundation

/// 도구별 창 규격. `ROOM.json.budget` 에 복사되고 튜닝 가능하다.
public struct ToolBudgetSpec: Equatable, Sendable {
    public var tool: AgentRoomTool
    public var window: Int
    public var trigger: Double
    public var reservedOutput: Int
    /// Codex 만 입력 전용 창에서 빼는 예약(13,000). 다른 도구는 0.
    public var reservedInput: Int
    public var handoffRatio: Double

    public init(
        tool: AgentRoomTool,
        window: Int,
        trigger: Double,
        reservedOutput: Int = 0,
        reservedInput: Int = 0,
        handoffRatio: Double = 0.8
    ) {
        self.tool = tool
        self.window = window
        self.trigger = trigger
        self.reservedOutput = reservedOutput
        self.reservedInput = reservedInput
        self.handoffRatio = handoffRatio
    }

    public static let claude = ToolBudgetSpec(
        tool: .claude,
        window: 1_000_000,
        trigger: 0.835
    )
    public static let codex = ToolBudgetSpec(
        tool: .codex,
        window: 272_000,
        trigger: 1.0,
        reservedInput: 13_000
    )
    public static let grok = ToolBudgetSpec(
        tool: .grok,
        window: 500_000,
        trigger: 0.8
    )
    public static let agy = ToolBudgetSpec(
        tool: .agy,
        window: 200_000,
        trigger: 0.8
    )

    public static let table: [AgentRoomTool: ToolBudgetSpec] = [
        .claude: .claude,
        .codex: .codex,
        .grok: .grok,
        .agy: .agy,
    ]

    public static func `default`(for tool: AgentRoomTool) -> ToolBudgetSpec {
        table[tool] ?? .claude
    }

    public func usable(initialInput: Int) -> Int {
        let raw: Int
        if reservedInput > 0 {
            raw = window - reservedInput - initialInput
        } else {
            raw = Int(Double(window) * trigger) - initialInput
        }
        return max(0, raw)
    }

    public func handoffAt(initialInput: Int) -> Int {
        let usableTokens = usable(initialInput: initialInput)
        return max(0, Int(Double(usableTokens) * handoffRatio))
    }
}
