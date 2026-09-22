import AppKit
import Foundation
import AgentRoomTerminalCore

extension AppModel {
    func dispatchAction(op: String, roomID: String) async throws {
        switch op {
        case "open", "open-gui":
            try await actions.openRoom(id: roomID)
        case "smoke":
            // smoke 진단 프로브 GUI 트리거
            break
        case "close":
            try await actions.closeRoom(id: roomID)
        case "handoff":
            try await actions.handoff(roomID: roomID)
        case "simulate":
            try await actions.simulate(roomID: roomID)
        case "habits":
            try await actions.showHabits(roomID: roomID)
        default:
            throw RoomActionError.notAvailable(op)
        }
    }

    func cleanupTerminalSession(roomID: String) {
        if let bridge = terminalCache.bridges.removeValue(forKey: roomID) {
            bridge.disconnect()
        }
        if let engine = terminalCache.engines.removeValue(forKey: roomID) {
            engine.terminate()
        }
        terminalCache.observers.removeValue(forKey: roomID)
    }

    func attachWalls(for node: RoomSummary) async {
        let sessionID = node.sessionID ?? ""
        let env = ProcessInfo.processInfo.environment
        do {
            let result = try SessionAttach.run(SessionAttachRequest(
                sessionID: sessionID,
                roomID: node.id,
                environment: env,
                homeDirectory: env["HOME"] ?? ""
            ))
            roomSurface.wallEnforcementByRoom[node.id] = result.enforcement
            lastAction = "attach:\(result.sessionID)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSessionForSelectedRoom() async {
        guard let id = selectedID else { return }
        cleanupTerminalSession(roomID: id)
        await runRoomAction(op: "open", roomID: id)
        await refresh()
    }

    func closeSessionForSelectedRoom() async {
        guard let id = selectedID else { return }
        cleanupTerminalSession(roomID: id)
        await runRoomAction(op: "close", roomID: id)
        await refresh()
    }

    func runVerdictForSelectedRoom() async {
        guard let id = selectedID else { return }
        await runRoomAction(op: "simulate", roomID: id)
    }

    func openWorkFolderForSelectedRoom() {
        guard let id = selectedID, let url = try? RoomFolderLocator.find(roomID: id) else { return }
        NSWorkspace.shared.open(url)
    }

    func takeSeat(for node: RoomSummary) async {
        selectRoom(id: node.id)
        cleanupTerminalSession(roomID: node.id)
        await runRoomAction(op: "open", roomID: node.id)
        await refresh()
    }

    func exclusionLines(for node: RoomSummary) -> [(cli: String, reason: String)] {
        let roomID = (node.kind == .appTile && node.parentID != nil) ? (node.parentID ?? node.id) : node.id
        let tools: [String] = (node.kind == .appTile && node.status == .blocked) ? [node.title] : (roomSurface.excludedToolsByRoom[roomID] ?? [])
        let reasons = roomSurface.exclusionReasons[roomID] ?? [:]
        return tools.map { cli in
            (cli, reasons[cli] ?? "")
        }
    }

    func restoreFactoryTuning() {
        tuning = .factory
        tuningSource.apply(tuning)
        publishMirror()
    }

    func persistTuning() {
        tuningSource.apply(tuning)
    }

    func probeDaemon() {
        var probe = DaemonClient(
            socketURL: AppPaths.daemonSocketURL(),
            spawnIfMissing: false
        )
        if let existing = daemonClient {
            probe.socketURL = existing.socketURL
            probe.authority = existing.authority
            probe.roomSession = existing.roomSession
        }
        let status = StateMirrorAdoption.daemonStatus(client: probe)
        daemonRunning = status.running
        daemonGeneration = status.generation
    }

    func publishMirror() {
        var fields = StateMirrorAdoption.fixtureFields(
            nodes: nodes,
            daemonRunning: daemonRunning,
            daemonGeneration: daemonGeneration
        )
        if !usingFixture {
            fields.rooms = roomSurface.realRoomCount
        }
        StateMirrorAdoption.publish(fields, lastError: errorMessage)
    }

    func liveSessionsByRoomDir() -> [String: String] {
        guard daemonRunning else { return [:] }
        var probe = DaemonClient(socketURL: AppPaths.daemonSocketURL(), spawnIfMissing: false)
        probe.authority = SessionAuthorizer.commandRoomAuthority
        let response: DaemonResponse
        let fallback: [String: String] = Dictionary()
        do {
            response = try probe.send(.listSessions())
        } catch {
            daemonRunning = false
            return fallback
        }
        guard response.ok else { return [:] }
        var table: [String: String] = [:]
        for item in response.result?["sessions"]?.array ?? [] {
            guard let dir = item["roomDir"]?.string, let id = item["sessionID"]?.string else { continue }
            table[SessionAuthorizer.standardized(dir)] = id
        }
        return table
    }
}
