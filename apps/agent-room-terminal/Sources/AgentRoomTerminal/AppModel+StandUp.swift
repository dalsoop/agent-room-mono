import Foundation
import SwiftUI
import AgentRoomTerminalCore
import RoomKit

extension AppModel {
    func loadStandUpCatalog() async {
        roomSurface.standUpTenants = RoomActionBinding.tenantSlugs()
        do {
            roomSurface.standUpBlueprints = try RoomStandUpClient.listBlueprints()
            errorMessage = nil
        } catch {
            roomSurface.standUpBlueprints = []
            errorMessage = String(describing: error)
        }
    }

    func reloadSeatChains() {
        let url = RoomGraphSeatChainReader.file()
        do {
            roomSurface.seatChains = .loaded(try RoomGraphSeatChainReader.load(url: url))
        } catch {
            roomSurface.seatChains = .failed(String(describing: error))
        }
    }

    func startSeatChainWatch() {
        let url = RoomGraphSeatChainReader.file()
        let watcher = RoomGraphFileWatcher(fileURL: url) { [weak self] in
            Task { @MainActor in
                self?.reloadSeatChains()
            }
        }
        roomSurface.seatChainWatcher = watcher
        watcher.start()
    }
}
