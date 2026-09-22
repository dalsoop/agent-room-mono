import Foundation
import LocalizationKit

/// 방 사이 흐름
extension SnapshotBuilder {
    func buildFlows(
        active: [PlacementDTO],
        archived: [PlacementDTO],
        waiting: [PlacementDTO],
        skills _: TwinNode
    ) -> [TwinFlow] {
        var flows: [TwinFlow] = []
        var no = 1
        if !waiting.isEmpty {
            flows.append(TwinFlow(from: "lobby", to: "work-rooms", no: no, label: CLILocalization.format("SnapshotBuilder+Flows.label", waiting.count), state: .queue))
            no += 1
        }
        if !archived.isEmpty {
            flows.append(TwinFlow(from: "work-rooms", to: "archive", no: no, label: CLILocalization.format("SnapshotBuilder+Flows.label-2", archived.count), state: .done))
            no += 1
        }
        for placement in active {
            if let room = placement.rooms?.first {
                flows.append(TwinFlow(from: placement.id, to: room.id, no: no, label: CLILocalization.string("SnapshotBuilder+Flows.label-3"), state: .exec))
                no += 1
            }
        }
        return flows
    }

}
