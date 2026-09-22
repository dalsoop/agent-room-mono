import Foundation
import AgentRoomTerminalCore

enum EventsCommand {
    static func run(_ args: [String]) {
        var rest = Array(args.dropFirst())
        let json = CLIArgs.takeJSON(&rest)
        let follow = takeFollow(&rest)
        let since = takeSince(&rest) ?? 0

        guard let roomID = rest.first, !roomID.isEmpty else {
            CLIIO.fail("usage: events <room-id> [--since N] [--follow] [--json]", code: CLIExit.usage)
        }

        let env = ProcessInfo.processInfo.environment
        let roomURL: URL
        do {
            roomURL = try requireRoom(roomID: roomID, environment: env)
        } catch {
            CLIIO.fail("room not found: \(roomID)")
        }

        if follow {
            runFollow(roomURL: roomURL, since: since, json: json)
        } else {
            runStatic(roomURL: roomURL, since: since, json: json)
        }
    }

    private static func runStatic(roomURL: URL, since: Int, json: Bool) {
        let log = RoomEventLog(roomURL: roomURL)
        let result = log.read(since: since)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            do {
                let data = try encoder.encode(result.events)
                guard let str = String(data: data, encoding: .utf8) else {
                    CLIIO.fail("failed to format events json string")
                }
                print(str)
            } catch {
                CLIIO.fail("failed to encode events: \(error.localizedDescription)")
            }
        } else {
            for event in result.events {
                printEvent(event)
            }
        }
    }

    private static func runFollow(roomURL: URL, since: Int, json: Bool) {
        let client = DaemonCommand.commandRoomClient()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        do {
            try client.subscribeEvents(roomDir: roomURL.path, since: since) { event in
                if json {
                    let data = try encoder.encode(event)
                    if let line = String(data: data, encoding: .utf8) {
                        print(line)
                        fflush(stdout)
                    }
                } else {
                    printEvent(event)
                    fflush(stdout)
                }
            }
        } catch {
            CLIIO.fail("events follow failed: \(error.localizedDescription)")
        }
    }

    private static func printEvent(_ event: RoomEvent) {
        var payloadSummary = ""
        if !event.payload.isEmpty {
            let parts = event.payload.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            payloadSummary = " (\(parts))"
        }
        print("[\(event.seq)] \(event.at) [\(event.kind)] actor:\(event.actor)\(payloadSummary)")
    }

    private static func takeFollow(_ args: inout [String]) -> Bool {
        if let idx = args.firstIndex(of: "--follow") {
            args.remove(at: idx)
            return true
        }
        return false
    }

    private static func takeSince(_ args: inout [String]) -> Int? {
        guard let idx = args.firstIndex(of: "--since") else { return nil }
        args.remove(at: idx)
        guard idx < args.count, let value = Int(args[idx]) else { return nil }
        args.remove(at: idx)
        return value
    }
}
