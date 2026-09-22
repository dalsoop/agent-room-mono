import AppKit
import SwiftUI

/// 마스코트 PNG — 앱 번들 리소스만. 없으면 이모지(뷰). 세션 tmp 경로는 쓰지 않는다.
@MainActor
enum Mascots {
    private static var cache: [String: NSImage?] = [:]

    static func image(_ key: String?) -> NSImage? {
        guard let key else { return nil }
        if let hit = cache[key] { return hit }
        let image = Bundle.main.url(forResource: key, withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        cache[key] = image
        return image
    }
}

/// 스윔레인 정의 — 인덱스는 Core TraceEvent.lane 계약과 일치.
enum TraceLane: Int, CaseIterable {
    case speech = 0, tool, subagent, artifact, uncalled

    var l10nKey: L10nKey {
        switch self {
        case .speech: return .laneSpeech
        case .tool: return .laneTool
        case .subagent: return .laneSubagent
        case .artifact: return .laneArtifact
        case .uncalled: return .laneUncalled
        }
    }
}

/// 노드 화면 앵커 — 흐름선 오버레이가 곡선 끝점을 찾는다.
struct NodeAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 흘림 배치 — 자식 크기가 제각각이어도 줄바꿈으로 채운다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = layout(subviews: subviews, maxWidth: proposal.width ?? 900)
        let union = frames.reduce(CGRect.zero) { $0.union($1) }
        return CGSize(width: union.maxX, height: union.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = layout(subviews: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needsWrap = x > 0 && x + size.width > maxWidth
            if needsWrap {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
