import XCTest
@testable import AgentRoomTerminalCore
import RoomKit

struct FixtureCompliance: ComplianceChecking, Sendable {
    var allowed: Set<String>

    func isCompliant(cli: String) throws -> Bool {
        allowed.contains(cli)
    }
}

final class RoomFolderTests: XCTestCase {
    var home: URL!
    var fakeBin: URL!
    var selfCLI: URL!
    var environment: [String: String]!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fm = FileManager.default
        home = fm.temporaryDirectory.appendingPathComponent(
            "room-folder-\(UUID().uuidString)", isDirectory: true
        )
        fakeBin = home.appendingPathComponent("fake-bin", isDirectory: true)
        try fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        selfCLI = fakeBin.appendingPathComponent("agent-room-terminal")
        try writeExecutable(selfCLI)
        try writeExecutable(fakeBin.appendingPathComponent("good-cli"))
        try writeExecutable(fakeBin.appendingPathComponent("bad-cli"))
        try writeExecutable(fakeBin.appendingPathComponent("extra-cli"))
        let path = "\(fakeBin.path):/usr/bin:/bin:/usr/local/bin"
        environment = [
            "SWIFT_APP_STATE_ROOT": home.path,
            "PATH": path,
        ]
    }

    override func tearDownWithError() throws {
        if let home {
            try FileManager.default.removeItem(at: home)
        }
        try super.tearDownWithError()
    }

    func testAssembleIsIdempotent() throws {
        let spec = makeSpec(preset: .toolbelt, toolbelt: ["good-cli"])
        let first = try RoomFolder.assemble(spec: spec)
        let snap1 = try snapshot(first.roomURL)
        let second = try RoomFolder.assemble(spec: spec)
        let snap2 = try snapshot(second.roomURL)
        XCTAssertEqual(snap1.keys, snap2.keys)
        XCTAssertEqual(snap1, snap2)
        XCTAssertEqual(first.roomURL, second.roomURL)
    }

    func testPresetBinContents() throws {
        let readOnly = try RoomFolder.assemble(spec: makeSpec(preset: .readOnly))
        XCTAssertEqual(Set(try binNames(at: readOnly.roomURL)), expectedBaseNames)

        let toolbelt = try RoomFolder.assemble(
            spec: makeSpec(preset: .toolbelt, toolbelt: ["good-cli"])
        )
        XCTAssertEqual(
            Set(try binNames(at: toolbelt.roomURL)),
            expectedBaseNames.union(["good-cli"])
        )

        let open = try RoomFolder.assemble(spec: makeSpec(preset: .open, toolbelt: ["good-cli"]))
        XCTAssertEqual(try binNames(at: open.roomURL), [])
    }

    func testNoncompliantToolsAreExcluded() throws {
        let spec = makeSpec(
            preset: .toolbelt,
            toolbelt: ["good-cli", "bad-cli"],
            allowed: [BaseBinFolder.selfCLIName, "good-cli"]
        )
        let result = try RoomFolder.assemble(spec: spec)
        XCTAssertFalse(try binNames(at: result.roomURL).contains("bad-cli"))
        XCTAssertTrue(try binNames(at: result.roomURL).contains("good-cli"))
        XCTAssertEqual(result.excludedTools, ["bad-cli"])
        let json = try roomJSON(at: result.roomURL)
        XCTAssertEqual(json.excludedTools, ["bad-cli"])
    }

    func testChildBinSubsetAndPresetRejection() throws {
        let parentSpec = makeSpec(
            slug: "gujo-seller-operations",
            preset: .toolbelt,
            toolbelt: ["good-cli"]
        )
        let parent = try RoomFolder.assemble(spec: parentSpec)
        let parentRef = RoomParentRef(
            roomID: parentSpec.roomID,
            slug: parentSpec.slug,
            preset: .toolbelt,
            walls: parentSpec.blueprint.walls,
            binNames: Set(parent.linkedTools),
            folderURL: parent.roomURL
        )

        var childOK = makeSpec(
            roomID: "child-ok",
            slug: "gujo-seller-review",
            preset: .readOnly,
            parent: parentRef
        )
        childOK.blueprint.walls = parentSpec.blueprint.walls
        let childResult = try RoomFolder.assemble(spec: childOK)
        XCTAssertTrue(childResult.roomURL.path.contains("/children/gujo-seller-review"))
        XCTAssertTrue(Set(childResult.linkedTools).isSubset(of: Set(parent.linkedTools)))

        var childWide = makeSpec(
            roomID: "child-wide",
            slug: "gujo-seller-open",
            preset: .open,
            parent: parentRef
        )
        childWide.blueprint.walls = parentSpec.blueprint.walls
        XCTAssertThrowsError(try RoomFolder.assemble(spec: childWide)) { error in
            guard case RoomAssemblyError.childPresetExceedsParent = error else {
                return XCTFail("expected childPresetExceedsParent, got \(error)")
            }
        }

        var childExtra = makeSpec(
            roomID: "child-extra",
            slug: "gujo-seller-extra",
            preset: .toolbelt,
            toolbelt: ["extra-cli"],
            parent: parentRef
        )
        childExtra.blueprint.walls = parentSpec.blueprint.walls
        XCTAssertThrowsError(try RoomFolder.assemble(spec: childExtra)) { error in
            guard case RoomAssemblyError.childBinExceedsParent = error else {
                return XCTFail("expected childBinExceedsParent, got \(error)")
            }
        }
    }

    func testEnvKeysAndClosedNetworkProxy() throws {
        var spec = makeSpec(preset: .readOnly)
        spec.blueprint.walls.network = false
        let result = try RoomFolder.assemble(spec: spec)
        let env = try parseEnv(at: result.roomURL.appendingPathComponent("env"))
        XCTAssertEqual(Set(env.keys), Set(RoomEnvFile.keys))
        XCTAssertEqual(env["ROOM_ID"], spec.roomID)
        XCTAssertEqual(env["ROOM_SESSION"], "")
        XCTAssertEqual(env["ROOM_TENANT"], "tenant:gujo")
        XCTAssertEqual(env["AGENT_TENANT"], "tenant:gujo")
        XCTAssertEqual(env["TENANT_ID"], "tenant:gujo")
        XCTAssertEqual(env["ROOM_PARENT"], "")
        XCTAssertEqual(env["ROOM_PRESET"], "readOnly")
        XCTAssertEqual(env["SWIFT_APP_STATE_ROOT"], spec.tenantPolicy.stateRoot)
        XCTAssertEqual(env["AGENT_WIKI_WORLD"], spec.tenantPolicy.wikiWorld)
        XCTAssertEqual(env["HTTP_PROXY"], RoomEnvFile.closedNetworkProxy)
        XCTAssertEqual(env["HTTPS_PROXY"], RoomEnvFile.closedNetworkProxy)
        XCTAssertEqual(env["ALL_PROXY"], RoomEnvFile.closedNetworkProxy)
        XCTAssertTrue(env["PATH"]?.contains("/bin:") ?? false)
        XCTAssertTrue(env["PATH"]?.contains("/_base-bin") ?? false)

        spec.blueprint.walls.network = true
        spec.blueprint.preset = .open
        let open = try RoomFolder.assemble(spec: spec)
        let openEnv = try parseEnv(at: open.roomURL.appendingPathComponent("env"))
        XCTAssertEqual(Set(openEnv.keys), Set(RoomEnvFile.keys))
        XCTAssertEqual(openEnv["HTTP_PROXY"], "")
        XCTAssertEqual(openEnv["PATH"], environment["PATH"])

        spec.blueprint.walls.network = .allow(domains: ["github.com"])
        spec.blueprint.preset = .toolbelt
        let allowValues = RoomEnvFile.makeValues(
            spec: spec,
            roomURL: result.roomURL,
            baseBin: fakeBin,
            proxyPort: 18080
        )
        XCTAssertEqual(allowValues["HTTP_PROXY"], "http://localhost:18080")
        XCTAssertEqual(allowValues["HTTPS_PROXY"], "http://localhost:18080")
        XCTAssertEqual(allowValues["ALL_PROXY"], "http://localhost:18080")
    }

    func testSlugRule() throws {
        XCTAssertThrowsError(try RoomFolder.assemble(spec: makeSpec(slug: "GujoSeller"))) { error in
            guard case RoomAssemblyError.invalidSlug = error else {
                return XCTFail("expected invalidSlug, got \(error)")
            }
        }
        XCTAssertThrowsError(try RoomFolder.assemble(spec: makeSpec(slug: "-leading"))) { error in
            guard case RoomAssemblyError.invalidSlug = error else {
                return XCTFail("expected invalidSlug, got \(error)")
            }
        }
        XCTAssertNoThrow(try RoomFolder.assemble(spec: makeSpec(slug: "gujo-seller-operations")))
    }

    func testBaseBinHasTenLinksAndNoForbidden() throws {
        let dir = try BaseBinFolder.ensure(
            environment: environment,
            homeDirectory: home.path,
            selfCLIPath: selfCLI.path
        )
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(Set(names), expectedBaseNames)
        XCTAssertEqual(names.count, BaseBinFolder.expectedCount)
        for banned in BaseBinFolder.forbiddenNames {
            XCTAssertFalse(names.contains(banned))
        }
    }

    func testChildWallsExceedParentThrows() throws {
        let parentSpec = makeSpec(slug: "gujo-seller-operations", preset: .toolbelt)
        let parent = try RoomFolder.assemble(spec: parentSpec)
        let parentRef = RoomParentRef(
            roomID: parentSpec.roomID,
            slug: parentSpec.slug,
            preset: .toolbelt,
            walls: RoomWallSnapshot(writePaths: ["apps/foo/**"], network: false),
            binNames: Set(parent.linkedTools),
            folderURL: parent.roomURL
        )
        var child = makeSpec(
            roomID: "child-wall",
            slug: "gujo-seller-other",
            preset: .readOnly,
            parent: parentRef
        )
        child.blueprint.walls = RoomWallSnapshot(writePaths: ["apps/bar/**"], network: false)
        XCTAssertThrowsError(try RoomFolder.assemble(spec: child)) { error in
            guard case RoomAssemblyError.childWallsExceedParent = error else {
                return XCTFail("expected childWallsExceedParent, got \(error)")
            }
        }
    }

    private var expectedBaseNames: Set<String> {
        Set(BaseBinFolder.posixNames + [BaseBinFolder.selfCLIName])
    }

    private func makeSpec(
        roomID: String = "room-1",
        slug: String = "gujo-seller-operations",
        preset: RoomWallPreset = .toolbelt,
        toolbelt: [String] = [],
        allowed: Set<String>? = nil,
        parent: RoomParentRef? = nil
    ) -> RoomAssemblySpec {
        let allow = allowed ?? Set([BaseBinFolder.selfCLIName, "good-cli", "extra-cli"])
        return RoomAssemblySpec(
            roomID: roomID,
            slug: slug,
            tenantSlug: "gujo",
            layoutID: "layout-1",
            parent: parent,
            blueprint: RoomBlueprintSnapshot(
                task: "판매 카탈로그를 운영한다",
                verdict: "gujo-catalog-manager doctor",
                brief: ["원장 CLI 만 쓴다"],
                toolbelt: toolbelt,
                preset: preset,
                walls: RoomWallSnapshot(writePaths: ["apps/foo/**"], network: true)
            ),
            tenantPolicy: RoomTenantPolicy(
                stateRoot: home.appendingPathComponent("state-root").path,
                wikiWorld: "tenant-gujo"
            ),
            budget: RoomBudgetSnapshot(
                window: 1_000_000,
                trigger: 0.835,
                initialInput: 100,
                reservedOutput: 0,
                usable: 834_900,
                handoffAt: 667_920
            ),
            compliance: FixtureCompliance(allowed: allow),
            environment: environment,
            homeDirectory: home.path,
            selfCLIPath: selfCLI.path
        )
    }

    private func writeExecutable(_ url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func binNames(at room: URL) throws -> [String] {
        let bin = room.appendingPathComponent("bin", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(atPath: bin.path).sorted()
    }

    private func parseEnv(at url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            out[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
        }
        return out
    }

    private func roomJSON(at room: URL) throws -> RoomJSONFile.Document {
        let url = room.appendingPathComponent("ROOM.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RoomJSONFile.Document.self, from: data)
    }

    private func snapshot(_ root: URL) throws -> [String: String] {
        let fm = FileManager.default
        let rels = try fm.subpathsOfDirectory(atPath: root.path).sorted()
        var out: [String: String] = [:]
        for rel in rels where !rel.contains(".DS_Store") {
            let url = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { continue }
            out[rel] = try snapshotEntry(url)
        }
        return out
    }

    private func snapshotEntry(_ url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            let dest = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            return "symlink:\(dest)"
        }
        return "file:" + (try String(contentsOf: url, encoding: .utf8))
    }
}
