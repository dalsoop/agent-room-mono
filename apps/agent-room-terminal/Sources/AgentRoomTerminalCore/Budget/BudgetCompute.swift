import Foundation
import RoomKit

/// 도구별 예산 스펙을 예산 상태로 묶는 얇은 접착.
/// 타입(BudgetState·BudgetPhase)과 국면 판정(BudgetJudgment)은 RoomKit 정본이고,
/// 여기서는 ToolBudgetSpec 해석만 한다.
public enum Budget {
    public static func compute(
        tool: AgentRoomTool,
        initialInput: Int,
        used: Int?,
        elapsedMinutes: Int?,
        estimatedWorkMinutes: Int?,
        spec: ToolBudgetSpec? = nil
    ) -> BudgetState {
        let resolved = spec ?? ToolBudgetSpec.default(for: tool)
        let usable = resolved.usable(initialInput: initialInput)
        let handoffAt = resolved.handoffAt(initialInput: initialInput)
        return BudgetState(
            window: resolved.window,
            trigger: resolved.trigger,
            initialInput: initialInput,
            reservedOutput: resolved.reservedOutput,
            usable: usable,
            used: used,
            handoffAt: handoffAt,
            elapsedMinutes: elapsedMinutes,
            estimatedWorkMinutes: estimatedWorkMinutes,
            state: BudgetJudgment.phase(
                used: used,
                usable: usable,
                handoffAt: handoffAt,
                elapsedMinutes: elapsedMinutes,
                estimatedWorkMinutes: estimatedWorkMinutes
            )
        )
    }
}
