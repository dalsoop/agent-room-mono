import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 캔버스에 배치된 개별 방 카드 정보.
public struct CanvasPlacedCard: Sendable, Equatable, Identifiable {
    public var id: String { room.id }
    public var room: RoomSummary
    public var position: CGPoint
    public var size: CGSize

    public init(room: RoomSummary, position: CGPoint, size: CGSize) {
        self.room = room
        self.position = position
        self.size = size
    }

    public var frame: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// 캔버스 레이아웃 엔진: 방 노드들을 직관적이고 compact한 2D 그리드로 배치.
public enum RoomCanvasLayout {
    public static let defaultCardWidth: CGFloat = 260
    public static let defaultCardHeight: CGFloat = 135
    public static let defaultGapX: CGFloat = 24
    public static let defaultGapY: CGFloat = 24

    /// 방 목록을 2D 캔버스 좌표계에 배치
    public static func layout(
        rooms: [RoomSummary],
        cardWidth: CGFloat = defaultCardWidth,
        cardHeight: CGFloat = defaultCardHeight,
        gapX: CGFloat = defaultGapX,
        gapY: CGFloat = defaultGapY
    ) -> [CanvasPlacedCard] {
        guard !rooms.isEmpty else { return [] }

        // 테넌트별로 그룹화하여 일관된 시각적 구획 제공
        let tenantGroups = RoomListFilter.groupByTenant(nodes: rooms)

        var placedCards: [CanvasPlacedCard] = []
        var currentY: CGFloat = cardHeight / 2 + 20

        for group in tenantGroups {
            let count = group.rooms.count
            if count == 0 { continue }

            // 한 행에 최대 3~4개 카드 배치
            let columns = max(1, min(4, count))
            for (index, room) in group.rooms.enumerated() {
                let col = index % columns
                let row = index / columns

                let x = CGFloat(col) * (cardWidth + gapX) + cardWidth / 2 + 20
                let y = currentY + CGFloat(row) * (cardHeight + gapY)

                placedCards.append(CanvasPlacedCard(
                    room: room,
                    position: CGPoint(x: x, y: y),
                    size: CGSize(width: cardWidth, height: cardHeight)
                ))
            }

            let totalRows = (count + columns - 1) / columns
            currentY += CGFloat(totalRows) * (cardHeight + gapY) + 30 // 테넌트 간 추가 여백
        }

        return placedCards
    }

    /// 모든 배체된 카드들을 감싸는 바운딩 박스(Bounding Box) 계산
    public static func boundingBox(for cards: [CanvasPlacedCard]) -> CGRect {
        guard let first = cards.first else {
            return CGRect(x: 0, y: 0, width: 800, height: 600)
        }

        var minX = first.frame.minX
        var minY = first.frame.minY
        var maxX = first.frame.maxX
        var maxY = first.frame.maxY

        for card in cards.dropFirst() {
            let frame = card.frame
            minX = min(minX, frame.minX)
            minY = min(minY, frame.minY)
            maxX = max(maxX, frame.maxX)
            maxY = max(maxY, frame.maxY)
        }

        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}
