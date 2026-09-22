import AppScaffoldKit
import DualEntryKit
import PermissionKit
import SingleInstanceKit
import StateRootKit
import SwiftUI

@main
struct AgentRoomTerminalApp: App {
    @State private var model = AppModel()

    init() {
        DualEntryRules.exitIfMisusedFromIdentity()
        StateRootKit.ensureCustomerRoomStorage(slug: "agent-room-terminal")
        // MPM `--permission-bootstrap=` 은 2번째 인스턴스 — SingleInstance 예외.
        if !PermissionBootstrap.isRequested {
            SingleInstance.exitIfAlreadyRunning()
        }
        Task { @MainActor in
            _ = PermissionBootstrap.runIfRequested(appName: "AgentRoomTerminal")
            HealthPulse.publish(app: "agent-room-terminal")
        }
    }

    var body: some Scene {
        // 일반 창 앱 — 실행하면 바로 주 창이 뜬다(메뉴바 없음, 독 아이콘 표시).
        // 콘텐츠·관리 앱의 기본 형태다. 상주 글랜스 유틸이면 --kind menubar 로 만들 것.
        Window("AgentRoomTerminal", id: "main") {
            if PermissionBootstrap.isRequested {
                Color.clear.frame(width: 1, height: 1)
            } else {
                MainView(model: model)
                    .gujoManaged()
            }
        }
        .defaultSize(width: 1280, height: 720)

        Settings {
            RanodeSettingsHost.wrap(
                SettingsView(model: model)
                    .frame(minWidth: 480, minHeight: 360)
            )
        }
    }
}
