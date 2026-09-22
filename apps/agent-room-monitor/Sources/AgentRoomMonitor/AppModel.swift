import Foundation
import Observation
import LocalizationKit
import AgentRoomMonitorCore

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = AgentRoomMonitorService()

    var status: String = ""

    init() {
        // 창 앱은 뷰 .task 만으로는 실행 확인 게이트에서 미러가 안 나온다 —
        // 앱 시작 시 1회 로드·게시(2026-08-05 실측 교훈).
        Task { await self.refresh() }
    }

    /// 타입세이프 지역화 헬퍼.
    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: loc.string(key.rawValue), locale: .current, arguments: args)
    }

    func refresh() async {
        do {
            try service.ensureDurableStore()
            status = try await service.status()
            StateMirrorAdoption.publish(status: status.isEmpty ? "ok" : status)
        } catch {
            status = String(describing: error)
            StateMirrorAdoption.publish(status: "error")
        }
    }
}
