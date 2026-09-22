import SwiftUI

/// 시점 스윔레인 + 스크러버. 실데이터(TraceStore)만 표시 — 비었으면 정직한 빈 상태.
struct TracePane: View {
    @Environment(AppModel.self) private var app
    @Bindable var board: BoardModel

    var body: some View {
        /* 스크러버는 항상 — born 되감기는 span 이벤트가 없어도 실데이터로 동작한다. */
        VStack(spacing: 8) {
            if visibleEvents.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    laneStack(in: geo.size)
                }
            }
            scrubber
            Text(app.L(.traceScrubHint)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(app.L(.traceEmptyTitle)).font(.system(size: 13, weight: .bold))
            Text(app.L(.traceEmptyBody))
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleEvents: [VTraceEvent] {
        let root = board.effectiveRoot
        return board.world.events.filter { event in
            guard event.t <= board.t else { return false }
            guard let roomID = event.roomID else { return true }
            if root.id == board.world.host.id { return true }
            return roomID == root.id || root.find(roomID) != nil
        }
    }

    private func laneStack(in size: CGSize) -> some View {
        let labelWidth: CGFloat = 118
        let plotWidth = size.width - labelWidth - 20
        let laneHeight = (size.height - 8) / CGFloat(TraceLane.allCases.count)
        return ZStack(alignment: .topLeading) {
            ForEach(TraceLane.allCases, id: \.rawValue) { lane in
                laneBackground(lane, labelWidth: labelWidth, plotWidth: plotWidth, laneHeight: laneHeight)
            }
            ForEach(visibleEvents) { event in
                eventView(event, labelWidth: labelWidth, plotWidth: plotWidth, laneHeight: laneHeight)
            }
        }
    }

    private func laneBackground(_ lane: TraceLane, labelWidth: CGFloat, plotWidth: CGFloat, laneHeight: CGFloat) -> some View {
        let y = CGFloat(lane.rawValue) * laneHeight
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(lane.rawValue % 2 == 0 ? 0.045 : 0.02))
                .frame(width: plotWidth, height: laneHeight - 2)
                .offset(x: labelWidth, y: y)
            Text(app.L(lane.l10nKey))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(lane == .uncalled ? VColor.gate : Color(red: 0.55, green: 0.63, blue: 0.7))
                .frame(width: labelWidth - 10, height: laneHeight, alignment: .trailing)
                .offset(y: y)
        }
    }

    @ViewBuilder
    private func eventView(_ event: VTraceEvent, labelWidth: CGFloat, plotWidth: CGFloat, laneHeight: CGFloat) -> some View {
        let window = board.timeWindow
        let span = max(1, window.upperBound - window.lowerBound)
        let x = labelWidth + plotWidth * (event.t - window.lowerBound) / span
        let y = CGFloat(event.lane) * laneHeight
        if event.diamond {
            diamondView(event).offset(x: x - 5, y: y + laneHeight / 2 - 6)
        } else {
            spanView(event, plotWidth: plotWidth, laneHeight: laneHeight).offset(x: x, y: y + laneHeight * 0.2)
        }
    }

    private func diamondView(_ event: VTraceEvent) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(VColor.accent).frame(width: 9, height: 9).rotationEffect(.degrees(45))
            Text(event.label).font(.system(size: 9.5))
                .foregroundStyle(Color(red: 0.66, green: 0.73, blue: 0.8)).lineLimit(1).frame(minWidth: 0)
        }
        .onTapGesture { board.select(span: event) }
    }

    private func spanView(_ event: VTraceEvent, plotWidth: CGFloat, laneHeight: CGFloat) -> some View {
        let clipped = min(event.dur, board.t - event.t)
        let window = board.timeWindow
        let span = max(1, window.upperBound - window.lowerBound)
        let width = max(8, plotWidth * clipped / span)
        let line: Color = lineColor(event)
        return RoundedRectangle(cornerRadius: 4)
            .fill(line.opacity(0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(line, style: .init(lineWidth: 1.1, dash: event.dashed ? [5, 4] : []))
            )
            .frame(width: width, height: laneHeight * 0.55)
            .overlay(alignment: .leading) {
                Text(event.label).font(.system(size: 9.5)).lineLimit(1).frame(minWidth: 0).fixedSize().padding(.leading, 6)
            }
            .onTapGesture { board.select(span: event) }
    }

    private func lineColor(_ event: VTraceEvent) -> Color {
        guard !event.dashed else { return VColor.gate }
        guard event.state != .exec else { return VColor.exec }
        return Color(red: 0.55, green: 0.63, blue: 0.7)
    }

    private var scrubber: some View {
        let window = board.timeWindow
        let current = Date(timeIntervalSince1970: board.t)
        let start = Date(timeIntervalSince1970: window.lowerBound)
        return HStack(spacing: 12) {
            Text(start.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: $board.t, in: window)
            Text(String(format: app.L(.traceTime),
                        current.formatted(date: .abbreviated, time: .shortened), ""))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(VColor.accent)
                .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }
}
