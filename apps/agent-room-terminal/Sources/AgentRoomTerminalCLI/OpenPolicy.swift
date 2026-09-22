import Foundation
import AgentRoomTerminalCore
import RoomKit

enum OpenPolicy {
    typealias VerdictStatus = RoomVerdictStatus
    typealias OpenedSession = RoomOpenedSession
    typealias ListedSession = RoomListedSession

    static func isOccupied(occupant: String, occupantSession: String) -> Bool {
        RoomOpenPipeline.isOccupied(occupant: occupant, occupantSession: occupantSession)
    }

    static func reusedSessionID(
        occupied: Bool,
        roomPath: String,
        sessions: [(sessionID: String, roomDir: String)]
    ) -> String? {
        reusedSessionID(
            occupied: occupied,
            roomPath: roomPath,
            sessions: sessions.map {
                ListedSession(sessionID: $0.sessionID, roomDir: $0.roomDir, sessionRole: "")
            }
        )
    }

    static func reusedSessionID(
        occupied: Bool,
        roomPath: String,
        sessions: [ListedSession],
        preferRole: String? = nil,
        excluding: String? = nil
    ) -> String? {
        RoomOpenPipeline.reusedSessionID(
            occupied: occupied,
            roomPath: roomPath,
            sessions: sessions,
            preferRole: preferRole,
            excluding: excluding
        )
    }

    static func seatbeltProfile(
        preset: RoomWallPreset,
        roomPath: String,
        writePaths: [String],
        network: NetworkWall,
        agentTools: [String] = [],
        proxyPort: UInt16? = nil,
        workdir: String? = nil
    ) -> String? {
        RoomOpenPolicy.seatbeltProfile(
            preset: preset,
            roomPath: roomPath,
            writePaths: writePaths,
            network: network,
            agentTools: agentTools,
            proxyPort: proxyPort,
            workdir: workdir
        )
    }

    static func verdictStatus(
        verdict: String,
        toolbelt: [String],
        excludedTools: [String],
        preset: RoomWallPreset = .toolbelt
    ) -> VerdictStatus {
        RoomOpenPipeline.verdictStatus(
            verdict: verdict,
            toolbelt: toolbelt,
            excludedTools: excludedTools,
            preset: preset
        )
    }

    static func successorHandle(sessionID: String) -> String {
        RoomOpenPolicy.successorHandle(sessionID: sessionID)
    }

    static func initialInput(for tool: AgentRoomTool) -> Int {
        RoomOpenPipeline.initialInput(for: tool)
    }
}
