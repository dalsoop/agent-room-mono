import Foundation

enum RoomDetailTab: String, CaseIterable, Identifiable, Sendable {
    case room
    case seat
    case permissions
    case context
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room: "방"
        case .seat: "좌석"
        case .permissions: "권한"
        case .context: "컨텍스트"
        case .events: "이벤트"
        }
    }
}
