import Foundation
import RoomKit

/// 허용 도구 중 사용량 잔여가 가장 큰 도구를 고른다. unknown 은 usable 로 본다.
public enum ToolSelector {
    public static func pick(
        allowed: [AgentRoomTool],
        states: [AgentRoomTool: BudgetState]
    ) -> AgentRoomTool? {
        let order = AgentRoomTool.allCases.filter { allowed.contains($0) }
        var best: AgentRoomTool?
        var bestRemain = Int.min
        for tool in order {
            guard let state = states[tool] else { continue }
            let remain = remainder(state)
            if remain > bestRemain {
                bestRemain = remain
                best = tool
            }
        }
        return best
    }

    public static func remainder(_ state: BudgetState) -> Int {
        guard let used = state.used else { return state.usable }
        return state.usable - used
    }
}
