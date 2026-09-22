import Foundation
import RoomKit

extension RoomOpenPipeline {
    func performOccupancy(
        hit: LedgerRoomHit,
        roomURL: URL,
        tool: AgentRoomTool,
        occupantString: String,
        opened: inout RoomOpenedSession
    ) async throws {
        let joinExisting = Self.shouldJoinExistingHandover(hit: hit, roomURL: roomURL)
        if joinExisting {
            opened.ledger = "joined-existing-handover"
        }
        let eventLog = RoomEventLog(roomURL: roomURL)
        let event = RoomEvent.occupied(
            agent: occupantString,
            sessionID: opened.sessionID,
            by: "agent-room-terminal"
        )
        try eventLog.append(event)
    }

    func closeOpenedSession(_ session: String) {
        do {
            try daemon.closeSession(sessionID: session)
        } catch {
            FileHandle.standardError.write(
                Data(("closeSession after occupy failure: \(error.localizedDescription)\n").utf8)
            )
        }
    }
}
