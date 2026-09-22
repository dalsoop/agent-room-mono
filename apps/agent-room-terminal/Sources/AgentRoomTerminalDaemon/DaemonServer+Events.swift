import Darwin
import Foundation
import AgentRoomTerminalCore

extension DaemonServer {
    func recordEvent(roomDir: String, event: RoomEvent) {
        do {
            let log = RoomEventLog(roomURL: URL(fileURLWithPath: roomDir))
            let written = try log.append(event)
            eventHub.broadcast(roomDir: roomDir, event: written)
        } catch {
            DaemonLog.append("record-event-failed: \(DaemonLog.describe(error))", to: logURL)
        }
    }

    func runEventsStream(client: Int32, request: DaemonRequest) {
        guard let roomDir = request.roomDir else {
            reportSocketError(
                DaemonProtocolError.requestFailed("events requires roomDir"),
                client: client
            )
            Darwin.close(client)
            return
        }
        let stream = AttachConnection(client: client, logURL: logURL, generation: generation)
        defer {
            stream.close()
        }

        let log = RoomEventLog(roomURL: URL(fileURLWithPath: roomDir))
        let initial = log.read(since: request.since ?? 0)
        for event in initial.events {
            let frame = DaemonStreamFrame(
                generation: generation,
                event: DaemonStreamEventName.roomEvent,
                roomEvent: event
            )
            stream.send(frame)
        }

        let (subID, dirKey) = eventHub.subscribe(roomDir: roomDir) { [weak stream] event in
            guard let stream else { return }
            let frame = DaemonStreamFrame(
                generation: stream.generation,
                event: DaemonStreamEventName.roomEvent,
                roomEvent: event
            )
            stream.send(frame)
        }
        defer {
            eventHub.unsubscribe(id: subID, roomDir: dirKey)
        }

        while true {
            do {
                let bytes = try UnixSocketIO.readSome(fd: client)
                if bytes.isEmpty { break }
            } catch {
                break
            }
        }
    }
}
