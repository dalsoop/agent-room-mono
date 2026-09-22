import Foundation
import AppPathsKit
import StateRootKit

/// 프로세스·경로 상수. 새 명령을 박지 말고 여기에 모은다.
///
/// 상태 경로는 전부 `StateRootKit` 아래에서 나온다 — 이 앱이 아는 경로 조각은
/// `stateDirectoryName` 과 그 밑 하위 디렉터리 이름뿐이고, 홈·테넌트(`~/.tenants/<t>/`)·
/// `SWIFT_APP_STATE_ROOT` 오버라이드·테스트 러너 격리 해석은 StateRootKit 이 한다.
/// `NSHomeDirectory()`/`homeDirectoryForCurrentUser` 로 홈을 직접 조립하지 않는다
/// (lint `hardcoded-state-root`).
public enum AppPaths: Sendable {
    public static let uname = "/usr/bin/uname"
    public static let open = "/usr/bin/open"
    public static let slug = "agent-room-monitor"

    /// 상태 루트 아래 이 앱의 디렉터리 이름 — 앱이 아는 유일한 상대 경로.
    public static let stateDirectoryName = ".agent-room-monitor"
    /// hook 트레이스 `<sessionID>.jsonl` 이 쌓이는 곳(`TraceStore`).
    public static let traceDirectoryName = "trace"
    /// 비교 모드 A|B 스냅샷 이력(`SnapshotArchive`).
    public static let snapshotsDirectoryName = "snapshots"
    /// 뷰 정의 `*.json` 정본(`ViewSpecStore`).
    public static let viewsDirectoryName = "views"

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

    /// 상태 디렉터리 아래 하위 디렉터리 — trace·snapshots·views 가 여기서 나온다.
    public static func stateSubdirectory(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        stateDirectory(environment: environment).appendingPathComponent(name, isDirectory: true)
    }

    /// 설정·작업 sqlite. UserDefaults·StateMirror 가 아니다.
    /// 함대 레이아웃(`Library/Application Support/net.ranode.agent-room-monitor/app.sqlite`)은 그대로 두고
    /// 홈 자리에 StateRootKit 루트를 넣는다 — 테넌트가 갈리면 sqlite 정본도 같이 갈린다.
    public static var sqliteFile: URL { sqliteFile() }

    public static func sqliteFile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        DurableAppLayout.sqliteURL(slug: slug, home: stateRoot(environment: environment))
    }
}
