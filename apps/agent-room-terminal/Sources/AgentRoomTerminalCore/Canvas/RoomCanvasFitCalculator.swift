import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 캔버스 화면 맞춤(Fit) 변환 정보 (줌 스케일 및 패닝 오프셋).
public struct CanvasViewportTransform: Sendable, Equatable {
    public var scale: Double
    public var offset: CGPoint

    public init(scale: Double, offset: CGPoint) {
        self.scale = scale
        self.offset = offset
    }

    public static let standard = CanvasViewportTransform(scale: 1.0, offset: .zero)
}

/// 화면 맞춤(Fit to Screen) 순수 계산기:
/// 모든 활성 노드의 바운딩 박스를 기준으로 화면 정중앙 정렬 및 적절한 줌 배율을 산출한다.
public enum RoomCanvasFitCalculator {
    public static func calculateFit(
        cards: [CanvasPlacedCard],
        viewport: CGSize,
        padding: CGFloat = 40,
        minScale: Double = 0.2,
        maxScale: Double = 1.5
    ) -> CanvasViewportTransform {
        guard !cards.isEmpty, viewport.width > 0, viewport.height > 0 else {
            return CanvasViewportTransform(scale: 1.0, offset: CGPoint(x: 20, y: 20))
        }

        let bounds = RoomCanvasLayout.boundingBox(for: cards)
        return calculateFit(
            bounds: bounds,
            viewport: viewport,
            padding: padding,
            minScale: minScale,
            maxScale: maxScale
        )
    }

    public static func calculateFit(
        bounds: CGRect,
        viewport: CGSize,
        padding: CGFloat = 40,
        minScale: Double = 0.2,
        maxScale: Double = 1.5
    ) -> CanvasViewportTransform {
        guard viewport.width > 0, viewport.height > 0 else {
            return .standard
        }

        let contentWidth = bounds.width + padding * 2
        let contentHeight = bounds.height + padding * 2

        let scaleX = viewport.width / max(1, contentWidth)
        let scaleY = viewport.height / max(1, contentHeight)
        let rawScale = min(scaleX, scaleY)
        let clampedScale = min(maxScale, max(minScale, rawScale))

        // 카드의 바운딩 박스 중심을 뷰포트 정중앙에 배치
        let boundsCenterX = bounds.midX
        let boundsCenterY = bounds.midY

        let offsetX = (viewport.width / 2) - boundsCenterX * clampedScale
        let offsetY = (viewport.height / 2) - boundsCenterY * clampedScale

        return CanvasViewportTransform(
            scale: clampedScale,
            offset: CGPoint(x: offsetX, y: offsetY)
        )
    }
}
