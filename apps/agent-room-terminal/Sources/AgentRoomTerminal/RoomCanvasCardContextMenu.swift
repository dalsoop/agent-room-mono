import AgentRoomTerminalCore
import SwiftUI

/// Actions.dc.html 기반 캔버스 카드 우클릭 컨텍스트 메뉴.
struct RoomCanvasCardContextMenu: ViewModifier {
    let room: RoomSummary
    let model: AppModel

    private var isOccupied: Bool {
        if case .loaded(let feed) = model.roomSurface.seatChains,
           let chain = feed.chains[room.id] {
            return !chain.current.isEmpty
        }
        return !room.occupants.isEmpty
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            if isOccupied {
                occupiedMenu
            } else {
                vacantMenu
            }
        }
    }

    @ViewBuilder
    private var occupiedMenu: some View {
        Button(action: {
            model.selectRoom(id: room.id)
            model.viewMode = .terminal
        }) {
            Label(String(localized: "Open Terminal"), systemImage: "terminal")
        }

        Button(action: {
            model.requestRoomAction(op: "handoff", roomID: room.id)
        }) {
            Label(String(localized: "Handoff (Bottle)"), systemImage: "arrow.right.circle")
        }

        Button(action: {
            model.selectRoom(id: room.id)
            Task { await model.runVerdictForSelectedRoom() }
        }) {
            Label(String(localized: "Run Verdict"), systemImage: "play.circle")
        }

        Divider()

        Button(action: {
            Task { await model.attachWalls(for: room) }
        }) {
            Label(String(localized: "Attach Walls"), systemImage: "shield")
        }

        Button(action: {
            model.selectRoom(id: room.id)
            Task { await model.closeSessionForSelectedRoom() }
        }) {
            Label(String(localized: "Leave Room"), systemImage: "xmark.circle")
        }
    }

    @ViewBuilder
    private var vacantMenu: some View {
        Button(action: {
            Task { await model.takeSeat(for: room) }
        }) {
            Label(String(localized: "Seat Successor"), systemImage: "chair.lounge")
        }

        Button(action: {
            model.selectRoom(id: room.id)
            Task { await model.openSessionForSelectedRoom() }
        }) {
            Label(String(localized: "Resume Session"), systemImage: "play.fill")
        }

        Button(action: {
            model.selectRoom(id: room.id)
            model.openWorkFolderForSelectedRoom()
        }) {
            Label(String(localized: "Open Work Folder"), systemImage: "folder")
        }

        Divider()

        Button(action: {
            model.selectRoom(id: room.id)
            Task { await model.runVerdictForSelectedRoom() }
        }) {
            Label(String(localized: "Simulate Verdict"), systemImage: "play.circle")
        }
    }
}

extension View {
    func roomContextMenu(room: RoomSummary, model: AppModel) -> some View {
        modifier(RoomCanvasCardContextMenu(room: room, model: model))
    }
}
