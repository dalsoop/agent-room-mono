import Foundation
import XCTest
@testable import AgentRoomTerminalCore
import RoomKit

private struct TestCompliance: ComplianceChecking, Sendable {
    func isCompliant(cli: String) throws -> Bool { true }
}

final class RoomEnvFileTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fm = FileManager.default
        tempDir = fm.temporaryDirectory.appendingPathComponent(
            "room-env-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    /// (a) worktree `.git` 파일 → hooks-shared 경로 산출
    func testWorktreeGitFileResolvesHooksShared() throws {
        let fm = FileManager.default
        let bareDir = tempDir.appendingPathComponent("repo.bare", isDirectory: true)
        let hooksSharedDir = bareDir.appendingPathComponent("hooks-shared", isDirectory: true)
        try fm.createDirectory(at: hooksSharedDir, withIntermediateDirectories: true)

        let worktreeGitDir = bareDir
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent("worker-wt", isDirectory: true)
        try fm.createDirectory(at: worktreeGitDir, withIntermediateDirectories: true)

        let commondirFile = worktreeGitDir.appendingPathComponent("commondir")
        try Data("../..\n".utf8).write(to: commondirFile)

        let worktreeDir = tempDir.appendingPathComponent("worktree", isDirectory: true)
        try fm.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try Data("gitdir: \(worktreeGitDir.path)\n".utf8).write(to: gitFile)

        let subDir = worktreeDir
            .appendingPathComponent("apps", isDirectory: true)
            .appendingPathComponent("my-app", isDirectory: true)
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)

        let resolvedFromSubDir = RoomEnvFile.gitHooksPath(workdir: subDir.path)
        XCTAssertEqual(resolvedFromSubDir, hooksSharedDir.path)

        let resolvedFromRoot = RoomEnvFile.gitHooksPath(workdir: worktreeDir.path)
        XCTAssertEqual(resolvedFromRoot, hooksSharedDir.path)

        let roomURL = tempDir.appendingPathComponent("room", isDirectory: true)
        try fm.createDirectory(at: roomURL, withIntermediateDirectories: true)
        let baseBin = tempDir.appendingPathComponent("bin", isDirectory: true)

        let spec = makeSpec(
            writePaths: [subDir.path + "/**"],
            environment: ["PWD": worktreeDir.path]
        )
        let values = RoomEnvFile.makeValues(spec: spec, roomURL: roomURL, baseBin: baseBin)
        XCTAssertEqual(values["GIT_CONFIG_COUNT"], "1")
        XCTAssertEqual(values["GIT_CONFIG_KEY_0"], "core.hooksPath")
        XCTAssertEqual(values["GIT_CONFIG_VALUE_0"], hooksSharedDir.path)
    }

    /// (b) 일반 `.git` 디렉터리
    func testStandardGitDirectoryResolvesHooksShared() throws {
        let fm = FileManager.default
        let repoDir = tempDir.appendingPathComponent("standard-repo", isDirectory: true)
        let gitDir = repoDir.appendingPathComponent(".git", isDirectory: true)
        let hooksSharedDir = gitDir.appendingPathComponent("hooks-shared", isDirectory: true)
        try fm.createDirectory(at: hooksSharedDir, withIntermediateDirectories: true)

        let subDir = repoDir
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Core", isDirectory: true)
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)

        let resolved = RoomEnvFile.gitHooksPath(workdir: subDir.path)
        XCTAssertEqual(resolved, hooksSharedDir.path)

        let roomURL = tempDir.appendingPathComponent("room", isDirectory: true)
        try fm.createDirectory(at: roomURL, withIntermediateDirectories: true)
        let baseBin = tempDir.appendingPathComponent("bin", isDirectory: true)

        let spec = makeSpec(
            writePaths: ["Sources/Core/**"],
            environment: ["PWD": repoDir.path]
        )
        let values = RoomEnvFile.makeValues(spec: spec, roomURL: roomURL, baseBin: baseBin)
        XCTAssertEqual(values["GIT_CONFIG_COUNT"], "1")
        XCTAssertEqual(values["GIT_CONFIG_KEY_0"], "core.hooksPath")
        XCTAssertEqual(values["GIT_CONFIG_VALUE_0"], hooksSharedDir.path)
    }

    /// (c) hooks-shared 부재 → 키 없음
    func testMissingHooksSharedProducesNoGitConfigKeys() throws {
        let fm = FileManager.default
        let repoDir = tempDir.appendingPathComponent("no-hooks-repo", isDirectory: true)
        let gitDir = repoDir.appendingPathComponent(".git", isDirectory: true)
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let resolved = RoomEnvFile.gitHooksPath(workdir: repoDir.path)
        XCTAssertNil(resolved)

        let roomURL = tempDir.appendingPathComponent("room", isDirectory: true)
        try fm.createDirectory(at: roomURL, withIntermediateDirectories: true)
        let baseBin = tempDir.appendingPathComponent("bin", isDirectory: true)

        let spec = makeSpec(
            writePaths: ["Sources/**"],
            environment: ["PWD": repoDir.path]
        )
        let values = RoomEnvFile.makeValues(spec: spec, roomURL: roomURL, baseBin: baseBin)
        XCTAssertNil(values["GIT_CONFIG_COUNT"])
        XCTAssertNil(values["GIT_CONFIG_KEY_0"])
        XCTAssertNil(values["GIT_CONFIG_VALUE_0"])
        for key in values.keys {
            XCTAssertFalse(key.hasPrefix("GIT_CONFIG_"), "unexpected key \(key)")
        }

        try RoomEnvFile.write(spec: spec, roomURL: roomURL, baseBin: baseBin)
        let envContent = try String(contentsOf: roomURL.appendingPathComponent("env"), encoding: .utf8)
        XCTAssertFalse(envContent.contains("GIT_CONFIG_"))
    }

    /// (d) 기존 GIT_CONFIG_COUNT=1 과 병합
    func testMergesWithExistingGitConfigCount() throws {
        let fm = FileManager.default
        let repoDir = tempDir.appendingPathComponent("existing-config-repo", isDirectory: true)
        let gitDir = repoDir.appendingPathComponent(".git", isDirectory: true)
        let hooksSharedDir = gitDir.appendingPathComponent("hooks-shared", isDirectory: true)
        try fm.createDirectory(at: hooksSharedDir, withIntermediateDirectories: true)

        let roomURL = tempDir.appendingPathComponent("room", isDirectory: true)
        try fm.createDirectory(at: roomURL, withIntermediateDirectories: true)
        let baseBin = tempDir.appendingPathComponent("bin", isDirectory: true)

        let spec = makeSpec(
            writePaths: ["Sources/**"],
            environment: [
                "PWD": repoDir.path,
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "user.email",
                "GIT_CONFIG_VALUE_0": "worker@example.com",
            ]
        )
        let values = RoomEnvFile.makeValues(spec: spec, roomURL: roomURL, baseBin: baseBin)
        XCTAssertEqual(values["GIT_CONFIG_COUNT"], "2")
        XCTAssertEqual(values["GIT_CONFIG_KEY_0"], "user.email")
        XCTAssertEqual(values["GIT_CONFIG_VALUE_0"], "worker@example.com")
        XCTAssertEqual(values["GIT_CONFIG_KEY_1"], "core.hooksPath")
        XCTAssertEqual(values["GIT_CONFIG_VALUE_1"], hooksSharedDir.path)

        try RoomEnvFile.write(spec: spec, roomURL: roomURL, baseBin: baseBin)
        let envContent = try String(contentsOf: roomURL.appendingPathComponent("env"), encoding: .utf8)
        XCTAssertTrue(envContent.contains("GIT_CONFIG_COUNT=2"))
        XCTAssertTrue(envContent.contains("GIT_CONFIG_KEY_0=user.email"))
        XCTAssertTrue(envContent.contains("GIT_CONFIG_VALUE_0=worker@example.com"))
        XCTAssertTrue(envContent.contains("GIT_CONFIG_KEY_1=core.hooksPath"))
        XCTAssertTrue(envContent.contains("GIT_CONFIG_VALUE_1=\(hooksSharedDir.path)"))
    }

    private func makeSpec(
        roomID: String = "room-test",
        slug: String = "room-test-slug",
        writePaths: [String] = [],
        environment: [String: String] = [:]
    ) -> RoomAssemblySpec {
        RoomAssemblySpec(
            roomID: roomID,
            slug: slug,
            tenantSlug: "gujo",
            layoutID: "layout-1",
            blueprint: RoomBlueprintSnapshot(
                task: "테스트",
                verdict: "true",
                walls: RoomWallSnapshot(writePaths: writePaths, network: true)
            ),
            tenantPolicy: RoomTenantPolicy(
                stateRoot: tempDir.appendingPathComponent("state-root").path,
                wikiWorld: "tenant-gujo"
            ),
            budget: RoomBudgetSnapshot(
                window: 1000,
                trigger: 0.8,
                initialInput: 10,
                reservedOutput: 0,
                usable: 800,
                handoffAt: 600
            ),
            compliance: TestCompliance(),
            environment: environment,
            homeDirectory: tempDir.path
        )
    }
}
