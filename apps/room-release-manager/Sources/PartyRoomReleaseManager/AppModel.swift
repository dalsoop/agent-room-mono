import StateRootKit
import Foundation
import Observation
import LocalizationKit
import PartyRoomReleaseManagerCore

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = PartyRoomReleaseManagerService()

    var config: PartyRoomReleaseConfig
    var probe: ProjectProbe?
    var isBusy = false
    var lastLog: String = ""
    var statusLine: String = "—"
    var pathDraft: String = ""
    var repoDraft: String = ""
    var versionDraft: String = ""

    init() {
        let cfg = PartyRoomReleaseManagerService().loadConfig()
        self.config = cfg
        self.pathDraft = cfg.projectPath
        self.repoDraft = cfg.githubRepo
        self.versionDraft = cfg.versionHint
    }

    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: loc.string(key.rawValue), locale: .current, arguments: args)
    }

    func refresh() async {
        let p = await service.probe(config: config)
        probe = p
        statusLine = p.summaryLine
        StateMirrorAdoption.publish(
            status: p.isHealthy ? "ok" : "need-setup",
            projectPath: p.projectPath,
            artifactsReady: p.artifacts.filter(\.ready).count
        )
        HealthPulse.publish(app: "party-room-release-manager", 
            status: p.isHealthy ? "ok" : "need-setup",
            detail: p.summaryLine
        )
    }

    func applyConfigDrafts() {
        config.projectPath = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        config.githubRepo = repoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        config.versionHint = versionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try service.saveConfig(config)
            lastLog = "설정 저장됨"
        } catch {
            lastLog = L(.AppModelString, error.localizedDescription)
        }
    }

    func build(_ platform: PartyRoomPlatform) async {
        guard !isBusy else { return }
        isBusy = true
        lastLog = L(.AppModelString_2, platform.displayName)
        defer { isBusy = false }
        applyConfigDrafts()
        let result = await service.build(platform: platform, config: config)
        lastLog = result.log
        if !result.ok {
            lastLog += L(.AppModelString_3, platform.displayName)
        } else {
            lastLog += L(.AppModelString_4, platform.displayName)
        }
        await refresh()
    }

    func openProject() async {
        applyConfigDrafts()
        await service.openProject(config: config)
    }

    func openArtifacts() async {
        applyConfigDrafts()
        await service.openArtifactsFolder(config: config)
    }

    var releaseHint: String {
        service.githubReleaseHint(config: config)
    }
}
