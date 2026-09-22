import Foundation
import AgentRoomTerminalCore

enum CheckCommand {
    static func run(_ args: [String]) {
        let command = CLIArgs.value("--cmd", in: args) ?? ""
        let tool = CLIArgs.value("--tool", in: args)
        let verdict = RoomCommandCheck.evaluate(
            command: command,
            tool: tool,
            environment: ProcessInfo.processInfo.environment
        )
        switch verdict {
        case .allow:
            exit(CLIExit.ok)
        case .deny(let reason):
            FileHandle.standardError.write(Data((reason + "\n").utf8))
            exit(CLIExit.checkDeny)
        }
    }
}
