import Foundation
import AppScaffoldKit
import AgentRoomTerminalCore
import SingleInstanceKit

// Cloud Apps 게이트 — GUI 의 `.gujoManaged()` 와 대칭인 CLI 진입 한 줄.
GujoManaged.exitIfNotEntitledSync(
    allowing: [
        "help", "-h", "--help", "version", "-V", "--version",
        "capabilities", "check", "open", "close", "exec", "tree",
        "snapshot", "budget", "handoff", "simulate", "habit",
        "daemon", "usage", "tuning", "open-gui", "smoke", "events",
        "launch-log", "doctor", "profile-lock", "checkpoint", "runs",
        "precompute", "delta", "synapses",
    ]
)

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"

SingleInstanceCLI.autoGuard()

switch cmd {
case "help", "-h", "--help":
    HelpCommand.run()
case "version", "-V", "--version":
    VersionCommand.run()
case "capabilities":
    CapabilitiesCommand.run()
case "doctor":
    DoctorCommand.run(args)
case "open-gui":
    OpenGUICommand.run()
case "open":
    OpenCommand.run(args)
case "close":
    CloseCommand.run(args)
case "exec":
    ExecCommand.run(args)
case "smoke":
    SmokeCommand.run(args)
case "tree":
    TreeCommand.run(args)
case "snapshot":
    SnapshotCommand.run(args)
case "check":
    CheckCommand.run(args)
case "budget":
    BudgetCommand.run(args)
case "handoff":
    HandoffCommand.run(args)
case "simulate":
    SimulateCommand.run(args)
case "habit":
    HabitCommand.run(args)
case "daemon":
    DaemonCommand.run(args)
case "usage":
    UsageCommand.run(args)
case "tuning":
    TuningCommand.run(args)
case "events":
    EventsCommand.run(args)
case "launch-log":
    LaunchLogCommand.run(args)
case "profile-lock":
    ProfileLockCommand.run(args)
case "checkpoint":
    CheckpointCommand.run(args)
case "runs":
    RunsCommand.run(args)
case "precompute":
    PrecomputeCommand.run(args)
case "delta":
    DeltaCommand.run(args)
case "synapses":
    SynapsesCommand.run(args)
default:
    FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
    HelpCommand.run()
    exit(CLIExit.usage)
}
