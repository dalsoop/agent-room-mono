import Foundation
import AgentRoomTerminalCore

enum TuningCommand {
    static func run(_ args: [String]) {
        let store = TuningStore.default()
        let rest = Array(args.dropFirst())
        let sub = rest.first ?? "show"
        do {
            switch sub {
            case "show":
                CLIIO.printOKObject(try store.show().jsonObject())
            case "set":
                try runSet(Array(rest.dropFirst()), store: store)
            default:
                CLIIO.fail("usage: tuning show|set <key> <value>", code: CLIExit.usage)
            }
        } catch {
            CLIIO.fail(error.localizedDescription)
        }
    }

    private static func runSet(_ args: [String], store: TuningStore) throws {
        guard args.count >= 2 else {
            CLIIO.fail("usage: tuning set <key> <value>", code: CLIExit.usage)
        }
        let values = try store.set(key: args[0], value: args[1])
        CLIIO.printOKObject(values.jsonObject())
    }
}
