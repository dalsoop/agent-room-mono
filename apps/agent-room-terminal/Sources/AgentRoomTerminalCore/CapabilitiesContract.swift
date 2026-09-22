import Foundation
import InteropKit

/// PATH CLI `capabilities` 정본. InteropKit 필드 + `dryRun` + `stateRoot.env`.
public struct CapabilitiesContract: Codable, Equatable, Sendable {
    public static let cliName = "agent-room-terminal"
    public static var version: String { RoomCLIVersion.current() }
    public static let stateRootEnv = "SWIFT_APP_STATE_ROOT"
    public static let purpose =
        "Assemble room folders, run a dedicated terminal daemon, and enforce room walls (벽은 RoomKit 컴파일러가 계산한다)."

    public struct Command: Codable, Equatable, Sendable {
        public var name: String
        public var summary: String
        public var json: Bool
        public var dryRun: Bool

        public init(name: String, summary: String, json: Bool, dryRun: Bool = false) {
            self.name = name
            self.summary = summary
            self.json = json
            self.dryRun = dryRun
        }
    }

    public struct StateFile: Codable, Equatable, Sendable {
        public var path: String
        public var what: String
    }

    public struct Health: Codable, Equatable, Sendable {
        public var command: String
        public var freshness: String
    }

    public struct Dependency: Codable, Equatable, Sendable {
        public var id: String
        public var kind: String
        public var ref: String
        public var required: Bool
        public var why: String
        public var commands: [String]?
    }

    public typealias StateRoot = Capabilities.StateRoot

    public var name: String
    public var purpose: String
    public var version: String
    public var cli: String
    public var commands: [Command]
    public var state: [StateFile]
    public var health: Health
    public var depends: [Dependency]
    public var stateRoot: StateRoot

    public static func make(
        cliPath: String,
        sqlitePath: String,
        freshness: String
    ) -> CapabilitiesContract {
        CapabilitiesContract(
            name: cliName,
            purpose: purpose,
            version: version,
            cli: cliPath,
            commands: commandTable,
            state: [
                StateFile(
                    path: sqlitePath,
                    what: "settings & work sqlite app.sqlite (source of truth; under the StateRootKit root)"
                ),
                StateFile(
                    path: freshness,
                    what: "app state summary (StateMirrorAdoption — observability mirror, not the source)"
                ),
            ],
            health: Health(
                command: "\(cliPath) capabilities",
                freshness: freshness
            ),
            depends: dependencyTable,
            stateRoot: StateRoot(env: stateRootEnv)
        )
    }

    public static let commandTable: [Command] = [
        Command(name: "capabilities", summary: "print this interop contract", json: true),
        Command(name: "help", summary: "print usage", json: false),
        Command(name: "version", summary: "print CLI stamp", json: false),
        Command(name: "open-gui", summary: "open the GUI app window (--room <roomID> to select a room)", json: false),
        Command(name: "open", summary: "assemble room folder; --attach-session registers walls without a PTY", json: true, dryRun: true),
        Command(name: "close", summary: "stop a room terminal and tick the ledger", json: true, dryRun: true),
        Command(name: "exec",
                summary: "run one command in room walls (--launch records session events)",
                json: true),
        Command(name: "smoke", summary: "run a one-shot non-interactive tool probe in a room", json: true),
        Command(name: "tree", summary: "list rooms with bottles, budget, occupants, and presets", json: true),
        Command(name: "snapshot", summary: "print the last N terminal lines of a room", json: true),
        Command(name: "check", summary: "hook gate for room wall bypass attempts (벽은 RoomKit 컴파일러가 계산한다)", json: false),
        Command(name: "budget", summary: "print room token and time budget state", json: true),
        Command(name: "handoff", summary: "write a handoff bottle, seat a successor, or show a bottle", json: true, dryRun: true),
        Command(name: "events", summary: "read or follow the append-only room event ledger (events.jsonl)", json: true),
        Command(name: "simulate", summary: "replay habits against a handoff bottle", json: true),
        Command(name: "habit", summary: "list, note, or promote room habits", json: true),
        Command(
            name: "habit promote",
            summary: "publish a stable habit to the tenant wiki world",
            json: true,
            dryRun: true
        ),
        Command(name: "launch-log", summary: "read or follow the room launch.log (exec --launch output)", json: true),
        Command(name: "daemon", summary: "start, stop, or show the terminal daemon", json: true),
        Command(name: "usage", summary: "print the room usage ledger", json: true),
        Command(name: "tuning", summary: "show or set shared GUI and CLI tuning values", json: true),
        Command(name: "doctor", summary: "audit runtime health and clean up leaked daemon sockets/resources", json: true),
        Command(name: "profile-lock", summary: "observe execution footprints to draft room walls and diagnose tenant violations", json: true),
        Command(name: "checkpoint", summary: "manage room work/ checkpoints and rollbacks", json: true),
        Command(name: "runs", summary: "list and show preserved run execution evidence", json: true),
        Command(name: "precompute", summary: "commit immutable precompute micro-spec and SHA-256 hash", json: true, dryRun: true),
        Command(name: "delta", summary: "evaluate empirical cognitive drift from git diff and kernel probes", json: true, dryRun: true),
        Command(name: "synapses", summary: "inspect room synapse topology and negative failure write masks", json: true),
    ]

    public static let dependencyTable: [Dependency] = [
        Dependency(
            id: "cli.agent-tenant-isolation-manager",
            kind: "cli",
            ref: "agent-tenant-isolation-manager",
            required: true,
            why: "compliance gate and tenant policy for room env",
            commands: ["check", "room show"]
        ),
        Dependency(
            id: "cli.agent-wiki",
            kind: "cli",
            ref: "agent-wiki",
            required: true,
            why: "habit promotion to tenant then shared wiki worlds",
            commands: ["task", "promotion"]
        ),
        Dependency(
            id: "system.zsh",
            kind: "system",
            ref: "zsh",
            required: true,
            why: "room shells are zsh -r or zsh",
            commands: nil
        ),
    ]
}
