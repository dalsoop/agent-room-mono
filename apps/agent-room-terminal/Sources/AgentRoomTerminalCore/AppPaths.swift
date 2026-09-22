import Foundation
@_exported import AppPathsKit
import StateRootKit
import CommandKit

/// 프로세스·경로 상수. 새 명령을 박지 말고 여기에 모은다.
///
/// 상태 경로는 전부 `StateRootKit` 아래에서 나온다 — 이 앱이 아는 경로 조각은
/// `stateDirectoryName` 하나뿐이고, 홈·테넌트(`~/.tenants/<t>/`)·`SWIFT_APP_STATE_ROOT`
/// 오버라이드·테스트 러너 격리 해석은 StateRootKit 이 한다. `NSHomeDirectory()`/
/// `homeDirectoryForCurrentUser`/`expandingTildeInPath` 로 홈을 직접 조립하지 않는다
/// (lint `hardcoded-state-root`).
public extension AppPaths {
    static let uname = "/usr/bin/uname"
    static var zsh: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? (["/bin", "zsh"].joined(separator: "/"))
    }
    static let env = "/usr/bin/env"
    static let sandboxExec = "/usr/bin/sandbox-exec"

    /// sandbox-exec 가 실제로 동작 가능한지 검사한다(중첩 샌드박스 등에서는 sandbox_apply 가 EPERM 을 낸다).
    public static let isSandboxAvailable: Bool = {
        guard FileManager.default.isExecutableFile(atPath: sandboxExec) else { return false }
        let check = CommandKitSync.run(sandboxExec, ["-p", "(version 1)(allow default)", "/usr/bin/true"], timeout: 2)
        return check.exitCode == 0
    }()
    public static let slug = "agent-room-terminal"
    public static let daemonDirectoryRelative = ".tenants/_daemon"
    public static let daemonSocketFileName = "agent-room-terminal.sock"
    public static let daemonGenerationFileName = "agent-room-terminal.generation"
    public static let daemonLogFileName = "agent-room-terminal.log"

    /// 상태 루트 아래 이 앱의 디렉터리 이름 — 앱이 아는 유일한 상대 경로.
    public static let stateDirectoryName = ".agent-room-terminal"

    /// StateRootKit 이 해석한 루트(홈 자리) — env 오버라이드 → 테스트 격리 → 테넌트 → 홈.
    public static func stateRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(fileURLWithPath: StateRootKit.resolve(environment: environment), isDirectory: true)
    }

    /// 앱 상태 디렉터리 — env 오버라이드면 해당 경로, 일반 고객 환경이면 기기 로컬 룸 저장소.
    public static func stateDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[StateRootKit.declaredEnv], !override.isEmpty {
            return StateRootKit.url(stateDirectoryName, environment: environment)
        }
        return StateRootKit.ensureCustomerRoomStorage(slug: slug)
    }

    /// 상태 디렉터리 아래 파일 — 설정 JSON·캐시 등 앱 고유 파일은 여기서 만든다.
    public static func stateFile(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        stateDirectory(environment: environment).appendingPathComponent(name, isDirectory: false)
    }

    /// 설정·작업 sqlite. UserDefaults·StateMirror 가 아니다.
    /// 함대 레이아웃(`Library/Application Support/net.ranode.agent-room-terminal/app.sqlite`)은 그대로 두고
    /// 홈 자리에 StateRootKit 루트를 넣는다 — 테넌트가 갈리면 sqlite 정본도 같이 갈린다.
    public static var sqliteFile: URL { sqliteFile() }

    public static func sqliteFile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        DurableAppLayout.sqliteURL(slug: slug, home: stateRoot(environment: environment))
    }

    /// Host-global daemon socket — `~/.tenants/_daemon/agent-room-terminal.sock`.
    /// Uses `resolveHost` so a tenant context does not move the socket.
    public static func daemonSocketURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.hostPath(
                "\(daemonDirectoryRelative)/\(daemonSocketFileName)",
                environment: environment
            )
        )
    }

    public static func daemonGenerationURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.hostPath(
                "\(daemonDirectoryRelative)/\(daemonGenerationFileName)",
                environment: environment
            )
        )
    }

    /// Daemon process log — host-global, not a room `state/` file.
    public static func daemonLogURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.hostPath(
                "\(daemonDirectoryRelative)/\(daemonLogFileName)",
                environment: environment
            )
        )
    }
}
