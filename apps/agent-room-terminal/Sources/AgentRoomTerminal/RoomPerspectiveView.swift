import SwiftUI
import RadialGraphUIKit
import TimelineGraphUIKit
import AgentRoomTerminalCore

/// 관점 뷰 (Perspective View): 상단 4단 동심원 레이더 그래프 + 하단 시간축 타임라인 트랙 및 스크러버
struct RoomPerspectiveView: View {
    var model: AppModel
    @State private var scrubberTime: Date = Date()

    init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        @Bindable var model = model
        // VSplitView 는 스스로 안 늘어난다
        VSplitView {
            // 상단: RadialRadarCanvasView (4단 동심원 레이더 캔버스 및 노드 선택)
            VStack(spacing: 0) {
                radarHeader
                RadialRadarCanvasView(
                    focusNode: model.focusRadialNode(),
                    nodes: model.radialNodes(),
                    selectedNodeID: $model.selectedID,
                    onSelectNode: { node in
                        model.selectRoom(id: node.id)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
            }
            .frame(minHeight: 220)

            // 하단: TimelineTrackBoardView (시간축 트랙 보드 및 수직 스크러버 커서)
            VStack(spacing: 0) {
                timelineHeader
                Divider()
                TimelineTrackBoardView(
                    tracks: model.timelineTracks(),
                    timeRange: model.timelineRange(),
                    scrubberTime: $scrubberTime,
                    onScrubberChanged: { _ in }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
            .frame(minHeight: 180)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("room-perspective-view")
    }

    private var radarHeader: some View {
        HStack(spacing: 8) {
            Label(model.L(.canvasViewModePerspective), systemImage: "scope")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            Text(verbatim: "\(model.nodes.count) Rooms")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var timelineHeader: some View {
        HStack(spacing: 8) {
            Label(model.L(.timelineActivity), systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(timeFormatter.string(from: scrubberTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}
