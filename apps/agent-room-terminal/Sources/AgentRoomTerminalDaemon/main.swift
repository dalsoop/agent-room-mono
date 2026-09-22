import SingleInstanceKit
import Darwin
import Dispatch
import Foundation
import AgentRoomTerminalCore
import ProcessLifecycleKit

SingleInstanceCLI.autoGuard()

struct DaemonArguments {
    var socketURL: URL
    var generationURL: URL
    var idleSeconds: TimeInterval

    static func parse(_ arguments: [String]) -> DaemonArguments {
        var socket = AppPaths.daemonSocketURL()
        var generation = AppPaths.daemonGenerationURL()
        var idle = DaemonDefaults.idleSeconds
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--socket", index + 1 < arguments.count {
                socket = URL(fileURLWithPath: arguments[index + 1])
                index += 2
                continue
            }
            if flag == "--generation", index + 1 < arguments.count {
                generation = URL(fileURLWithPath: arguments[index + 1])
                index += 2
                continue
            }
            if flag == "--idle-seconds", index + 1 < arguments.count {
                if let parsed = TimeInterval(arguments[index + 1]) {
                    idle = parsed
                }
                index += 2
                continue
            }
            index += 1
        }
        return DaemonArguments(socketURL: socket, generationURL: generation, idleSeconds: idle)
    }
}

func installTerminationTrap(server: DaemonServer) {
    ProcessSignalTrap.shared.onSignal(name: "agent-room-terminal-daemon-stop") { _ in
        server.stop()
    }
    ProcessSignalTrap.shared.install()
}

let parsed = DaemonArguments.parse(Array(CommandLine.arguments.dropFirst()))
let server = DaemonServer(
    socketURL: parsed.socketURL,
    generationURL: parsed.generationURL,
    tuning: DaemonTuning(idleSeconds: parsed.idleSeconds)
)
do {
    try server.start()
} catch {
    fputs("daemon start failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
installTerminationTrap(server: server)
server.waitUntilStopped()
