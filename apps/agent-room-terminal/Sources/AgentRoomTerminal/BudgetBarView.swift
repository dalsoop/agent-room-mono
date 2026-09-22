import SwiftUI
import AgentRoomTerminalCore

/// 예산 진행 막대와 텍스트를 표시하는 독립 뷰.
/// RoomDetailView 의 cyclomatic 분기 합을 줄이기 위해 분리했다.
struct BudgetBarView: View {
    var usage: RoomUsage
    var title: String
    var unknownText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let fraction = usage.fraction {
                ProgressView(value: fraction)
                    .tint(barColor)
            }
            Text(usageText)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private var usageText: String {
        RoomUsageText.format(usage: usage, unknownText: unknownText)
    }

    private var barColor: Color {
        guard let fraction = usage.fraction else { return .secondary }
        if fraction >= 1.0 { return .red }
        if fraction >= 0.8 { return .orange }
        return .green
    }
}
