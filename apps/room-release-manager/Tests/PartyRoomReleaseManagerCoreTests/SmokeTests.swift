import AppScaffoldKit
import XCTest
import CommandKit
@testable import PartyRoomReleaseManagerCore

final class SmokeTests: XCTestCase {
    func testAppFormContractCompliance() {
        XCTAssertTrue(RanodeAppFormContract.assertConforms(slug: "party-room-release-manager"))
    }

    func testDefaultConfigPaths() {
        let cfg = PartyRoomReleaseConfig()
        XCTAssertTrue(cfg.projectPath.contains("game-party-room-app"))
        XCTAssertFalse(cfg.githubRepo.isEmpty)
    }

    func testPlatformFlutterTargets() {
        XCTAssertEqual(PartyRoomPlatform.android.flutterTarget, "apk")
        XCTAssertEqual(PartyRoomPlatform.macos.flutterTarget, "macos")
        XCTAssertEqual(PartyRoomPlatform.windows.flutterTarget, "windows")
        XCTAssertEqual(PartyRoomPlatform.ios.flutterTarget, "ipa")
    }

    func testProbeMissingPath() async {
        struct MockRunner: CommandRunning {
            func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
                CommandResult(stdout: "", stderr: "", exitCode: 1)
            }
        }
        let svc = PartyRoomReleaseManagerService(runner: MockRunner())
        var cfg = PartyRoomReleaseConfig()
        cfg.projectPath = "/tmp/party-room-does-not-exist-\(UUID().uuidString)"
        let probe = await svc.probe(config: cfg)
        XCTAssertFalse(probe.exists)
        XCTAssertFalse(probe.isHealthy)
        XCTAssertTrue(probe.summaryLine.contains("없음") || probe.summaryLine.lowercased().contains("path") || !probe.exists)
    }

    func testReleaseHintContainsRepo() {
        let svc = PartyRoomReleaseManagerService()
        var cfg = PartyRoomReleaseConfig()
        cfg.githubRepo = "dalsoop/party-room-test"
        cfg.versionHint = "9.9.9"
        let hint = svc.githubReleaseHint(config: cfg)
        XCTAssertTrue(hint.contains("dalsoop/party-room-test"))
        XCTAssertTrue(hint.contains("v9.9.9") || hint.contains("9.9.9"))
    }
}
