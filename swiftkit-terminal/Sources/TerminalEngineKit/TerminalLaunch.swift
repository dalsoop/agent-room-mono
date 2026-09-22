import Foundation

/// 터미널 엔진 실행 컨텍스트.
/// 프로세스 실행에 필요한 디렉터리, 인수, 환경변수, 외형 및 tmux/샌드박스 설정을 캡슐화한다.
public struct TerminalLaunch: Sendable {
    public var cwd: String
    public var command: [String]
    public var environment: [String: String]
    public var appearance: TerminalAppearance
    public var tmuxName: String?
    public var backing: TmuxBacking?
    public var rawCommand: [String]?
    public var sandbox: PaneSandbox?

    public init(
        cwd: String,
        command: [String] = [],
        environment: [String: String] = [:],
        appearance: TerminalAppearance = .default,
        tmuxName: String? = nil,
        backing: TmuxBacking? = nil,
        rawCommand: [String]? = nil,
        sandbox: PaneSandbox? = nil
    ) {
        self.cwd = cwd
        self.command = command
        self.environment = environment
        self.appearance = appearance
        self.tmuxName = tmuxName
        self.backing = backing
        self.rawCommand = rawCommand
        self.sandbox = sandbox
    }

    /// `command` 별칭
    public var argv: [String] {
        get { command }
        set { command = newValue }
    }

    /// `environment` 별칭
    public var env: [String: String] {
        get { environment }
        set { environment = newValue }
    }
}

// 하위 호환 별칭
public typealias TerminalLaunchContext = TerminalLaunch
