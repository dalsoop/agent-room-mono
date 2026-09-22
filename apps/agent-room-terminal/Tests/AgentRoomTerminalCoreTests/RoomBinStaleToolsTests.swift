import Foundation
import XCTest
@testable import AgentRoomTerminalCore
import RoomKit
import InstallHealthKit

final class RoomBinStaleToolsTests: XCTestCase {
    func testStaleWarningIsDetectedAndToolIsExcludedFromBin() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(
            "room-stale-\(UUID().uuidString)", isDirectory: true
        )
        let fakeBin = home.appendingPathComponent("fake-bin", isDirectory: true)
        try fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let selfCLI = fakeBin.appendingPathComponent("agent-room-terminal")
        try writeExecutable(selfCLI, script: "#!/bin/sh\nexit 0\n")
        try writeExecutable(fakeBin.appendingPathComponent("fresh-cli"), script: "#!/bin/sh\nexit 0\n")
        try writeExecutable(
            fakeBin.appendingPathComponent("stale-cli"),
            script: """
            #!/bin/sh
            printf '%s\\n%s\\n' '설치본이 소스보다 낡았습니다' '{"ok":true}'
            exit 0
            """
        )
        try writeExecutable(
            fakeBin.appendingPathComponent("fail-cli"),
            script: "#!/bin/sh\necho fail >&2\nexit 1\n"
        )

        let environment = [
            "SWIFT_APP_STATE_ROOT": home.path,
            "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/local/bin",
        ]
        let spec = RoomAssemblySpec(
            roomID: "room-stale",
            slug: "gujo-seller-stale",
            tenantSlug: "gujo",
            layoutID: "layout-1",
            blueprint: RoomBlueprintSnapshot(
                task: "stale probe",
                verdict: "true",
                toolbelt: ["fresh-cli", "stale-cli", "fail-cli"],
                preset: .toolbelt,
                walls: RoomWallSnapshot(writePaths: ["apps/foo/**"], network: true)
            ),
            tenantPolicy: RoomTenantPolicy(stateRoot: home.path, wikiWorld: "tenant-gujo"),
            budget: RoomBudgetSnapshot(
                window: 1_000_000,
                trigger: 0.835,
                initialInput: 100,
                reservedOutput: 0,
                usable: 834_900,
                handoffAt: 667_920
            ),
            compliance: FixtureCompliance(
                allowed: [BaseBinFolder.selfCLIName, "fresh-cli", "stale-cli", "fail-cli"]
            ),
            environment: environment,
            homeDirectory: home.path,
            selfCLIPath: selfCLI.path
        )

        let result = try RoomFolder.assemble(spec: spec)
        let names = try fm.contentsOfDirectory(
            atPath: result.roomURL.appendingPathComponent("bin").path
        )
        // stale 도구는 판정을 오염시키지 않도록 방의 bin/ 에 링크되지 않아야 한다.
        XCTAssertFalse(names.contains("stale-cli"))
        XCTAssertTrue(names.contains("fresh-cli"))
        XCTAssertTrue(names.contains("fail-cli"))

        let jsonURL = result.roomURL.appendingPathComponent("ROOM.json")
        let document = try JSONDecoder().decode(
            RoomJSONFile.Document.self,
            from: Data(contentsOf: jsonURL)
        )
        XCTAssertEqual(document.staleTools, ["stale-cli"])
        XCTAssertTrue(document.excludedTools.contains("stale-cli"))
        XCTAssertFalse(document.staleTools.contains("fail-cli"))
        XCTAssertFalse(document.staleTools.contains("fresh-cli"))
        XCTAssertTrue(result.excludedTools.contains("stale-cli"))
        XCTAssertFalse(result.linkedTools.contains("stale-cli"))
    }

    func testSourceHashMismatchViaStampExcludesToolFromBin() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(
            "room-sourcehash-\(UUID().uuidString)", isDirectory: true
        )
        let fakeBin = home.appendingPathComponent("fake-bin", isDirectory: true)
        let fakeStamps = home.appendingPathComponent(".agent-ops/install-stamps", isDirectory: true)
        let fakeRepo = home.appendingPathComponent("fake-repo", isDirectory: true)
        let fakeApp = fakeRepo.appendingPathComponent("apps/my-tool-swift", isDirectory: true)

        try fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeStamps, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        // 소스 파일 생성
        let sourceFile = fakeApp.appendingPathComponent("Tool.swift")
        try "print(\"hello v2\")".write(to: sourceFile, atomically: true, encoding: .utf8)

        let selfCLI = fakeBin.appendingPathComponent("agent-room-terminal")
        let toolCLI = fakeBin.appendingPathComponent("my-tool")
        try writeExecutable(selfCLI, script: "#!/bin/sh\nexit 0\n")
        try writeExecutable(toolCLI, script: "#!/bin/sh\nexit 0\n")

        // 설치 스탬프에 소스와 다른 sourceHash 기록
        let stampJSON: [String: Any] = [
            "cli": "my-tool",
            "appPath": "apps/my-tool-swift",
            "repo": fakeRepo.path,
            "sourceHash": "outdated-hash-0000000000000000",
        ]
        let stampData = try JSONSerialization.data(withJSONObject: stampJSON)
        try stampData.write(to: fakeStamps.appendingPathComponent("my-tool.json"))

        let environment = [
            "SWIFT_APP_STATE_ROOT": home.path,
            "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/local/bin",
        ]
        let spec = RoomAssemblySpec(
            roomID: "room-sourcehash-test",
            slug: "gujo-sourcehash-test",
            tenantSlug: "gujo",
            layoutID: "layout-1",
            blueprint: RoomBlueprintSnapshot(
                task: "sourceHash probe",
                verdict: "true",
                toolbelt: ["my-tool"],
                preset: .toolbelt,
                walls: RoomWallSnapshot(writePaths: ["apps/foo/**"], network: true)
            ),
            tenantPolicy: RoomTenantPolicy(stateRoot: home.path, wikiWorld: "tenant-gujo"),
            budget: RoomBudgetSnapshot(
                window: 1_000_000,
                trigger: 0.835,
                initialInput: 100,
                reservedOutput: 0,
                usable: 834_900,
                handoffAt: 667_920
            ),
            compliance: FixtureCompliance(
                allowed: [BaseBinFolder.selfCLIName, "my-tool"]
            ),
            environment: environment,
            homeDirectory: home.path,
            selfCLIPath: selfCLI.path
        )

        let result = try RoomFolder.assemble(spec: spec)
        let names = try fm.contentsOfDirectory(
            atPath: result.roomURL.appendingPathComponent("bin").path
        )
        // sourceHash 불일치로 판정되어 방 bin/ 에 링크되지 않아야 한다.
        XCTAssertFalse(names.contains("my-tool"))
        XCTAssertTrue(result.excludedTools.contains("my-tool"))

        let jsonURL = result.roomURL.appendingPathComponent("ROOM.json")
        let document = try JSONDecoder().decode(
            RoomJSONFile.Document.self,
            from: Data(contentsOf: jsonURL)
        )
        XCTAssertEqual(document.staleTools, ["my-tool"])
        XCTAssertTrue(document.excludedTools.contains("my-tool"))
    }

    func testSourceHashMatchViaStampAllowsToolInBin() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(
            "room-match-\(UUID().uuidString)", isDirectory: true
        )
        let fakeBin = home.appendingPathComponent("fake-bin", isDirectory: true)
        let fakeStamps = home.appendingPathComponent(".agent-ops/install-stamps", isDirectory: true)
        let fakeRepo = home.appendingPathComponent("fake-repo", isDirectory: true)
        let fakeApp = fakeRepo.appendingPathComponent("apps/my-fresh-tool-swift", isDirectory: true)

        try fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeStamps, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        // 소스 파일 생성
        let sourceFile = fakeApp.appendingPathComponent("Tool.swift")
        try "print(\"hello fresh\")".write(to: sourceFile, atomically: true, encoding: .utf8)

        let selfCLI = fakeBin.appendingPathComponent("agent-room-terminal")
        let toolCLI = fakeBin.appendingPathComponent("my-fresh-tool")
        try writeExecutable(selfCLI, script: "#!/bin/sh\nexit 0\n")
        try writeExecutable(toolCLI, script: "#!/bin/sh\nexit 0\n")

        // 실제 sourceHash 계산 후 스탬프에 동일하게 기록
        let computedHash = InstallProvenance.sourceHash(
            appPath: "apps/my-fresh-tool-swift",
            root: fakeRepo.path
        )
        XCTAssertNotNil(computedHash)

        let stampJSON: [String: Any] = [
            "cli": "my-fresh-tool",
            "appPath": "apps/my-fresh-tool-swift",
            "repo": fakeRepo.path,
            "sourceHash": computedHash ?? "",
        ]
        let stampData = try JSONSerialization.data(withJSONObject: stampJSON)
        try stampData.write(to: fakeStamps.appendingPathComponent("my-fresh-tool.json"))

        let environment = [
            "SWIFT_APP_STATE_ROOT": home.path,
            "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/local/bin",
        ]
        let spec = RoomAssemblySpec(
            roomID: "room-match-test",
            slug: "gujo-match-test",
            tenantSlug: "gujo",
            layoutID: "layout-1",
            blueprint: RoomBlueprintSnapshot(
                task: "sourceHash probe",
                verdict: "true",
                toolbelt: ["my-fresh-tool"],
                preset: .toolbelt,
                walls: RoomWallSnapshot(writePaths: ["apps/foo/**"], network: true)
            ),
            tenantPolicy: RoomTenantPolicy(stateRoot: home.path, wikiWorld: "tenant-gujo"),
            budget: RoomBudgetSnapshot(
                window: 1_000_000,
                trigger: 0.835,
                initialInput: 100,
                reservedOutput: 0,
                usable: 834_900,
                handoffAt: 667_920
            ),
            compliance: FixtureCompliance(
                allowed: [BaseBinFolder.selfCLIName, "my-fresh-tool"]
            ),
            environment: environment,
            homeDirectory: home.path,
            selfCLIPath: selfCLI.path
        )

        let result = try RoomFolder.assemble(spec: spec)
        let names = try fm.contentsOfDirectory(
            atPath: result.roomURL.appendingPathComponent("bin").path
        )
        // sourceHash 일치하므로 정상적으로 bin/ 에 링크된다.
        XCTAssertTrue(names.contains("my-fresh-tool"))
        XCTAssertFalse(result.excludedTools.contains("my-fresh-tool"))

        let jsonURL = result.roomURL.appendingPathComponent("ROOM.json")
        let document = try JSONDecoder().decode(
            RoomJSONFile.Document.self,
            from: Data(contentsOf: jsonURL)
        )
        XCTAssertFalse(document.staleTools.contains("my-fresh-tool"))
        XCTAssertFalse(document.excludedTools.contains("my-fresh-tool"))
    }

    func testFixtureSourceHashGateInjection() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(
            "room-fixture-gate-\(UUID().uuidString)", isDirectory: true
        )
        let fakeBin = home.appendingPathComponent("fake-bin", isDirectory: true)
        try fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let selfCLI = fakeBin.appendingPathComponent("agent-room-terminal")
        try writeExecutable(selfCLI, script: "#!/bin/sh\nexit 0\n")
        try writeExecutable(fakeBin.appendingPathComponent("tool-a"), script: "#!/bin/sh\nexit 0\n")
        try writeExecutable(fakeBin.appendingPathComponent("tool-b"), script: "#!/bin/sh\nexit 0\n")

        let environment = [
            "SWIFT_APP_STATE_ROOT": home.path,
            "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/local/bin",
        ]
        let fixtureGate = FixtureSourceHashGate(staleTools: [
            "tool-a": "소스 콘텐츠가 바뀜(sourceHash 불일치)"
        ])
        let spec = RoomAssemblySpec(
            roomID: "room-fixture-test",
            slug: "gujo-fixture-test",
            tenantSlug: "gujo",
            layoutID: "layout-1",
            blueprint: RoomBlueprintSnapshot(
                task: "fixture gate probe",
                verdict: "true",
                toolbelt: ["tool-a", "tool-b"],
                preset: .toolbelt,
                walls: RoomWallSnapshot(writePaths: ["apps/foo/**"], network: true)
            ),
            tenantPolicy: RoomTenantPolicy(stateRoot: home.path, wikiWorld: "tenant-gujo"),
            budget: RoomBudgetSnapshot(
                window: 1_000_000,
                trigger: 0.835,
                initialInput: 100,
                reservedOutput: 0,
                usable: 834_900,
                handoffAt: 667_920
            ),
            compliance: FixtureCompliance(
                allowed: [BaseBinFolder.selfCLIName, "tool-a", "tool-b"]
            ),
            sourceHashGate: fixtureGate,
            environment: environment,
            homeDirectory: home.path,
            selfCLIPath: selfCLI.path
        )

        let result = try RoomFolder.assemble(spec: spec)
        let names = try fm.contentsOfDirectory(
            atPath: result.roomURL.appendingPathComponent("bin").path
        )
        XCTAssertFalse(names.contains("tool-a"))
        XCTAssertTrue(names.contains("tool-b"))
        XCTAssertTrue(result.excludedTools.contains("tool-a"))
        XCTAssertFalse(result.excludedTools.contains("tool-b"))
    }

    func testStdoutPrefixDetector() {
        XCTAssertTrue(StaleInstallProbe.hasWarning(in: "설치본이 소스보다 낡았습니다\n{\"ok\":true}\n"))
        XCTAssertTrue(StaleInstallProbe.hasWarning(in: "⚠ x: 설치본이 소스보다 낡았습니다 — hash\n{}"))
        XCTAssertFalse(StaleInstallProbe.hasWarning(in: "{\"ok\":true}\n"))
        XCTAssertFalse(StaleInstallProbe.hasWarning(in: ""))
    }

    private func writeExecutable(_ url: URL, script: String) throws {
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
