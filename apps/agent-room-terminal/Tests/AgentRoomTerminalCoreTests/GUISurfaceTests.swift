import Foundation
import XCTest
@testable import AgentRoomTerminalCore

/// GUI 타깃은 실행파일이라 import 할 수 없다. JSON 계약·L10n·결속 지점은 파일로 검증한다.
final class GUISurfaceTests: XCTestCase {
    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRefreshFillsActionResolverFromRoomFolders() throws {
        let text = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/AppModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("fillActionResolver"))
        XCTAssertTrue(text.contains("DictionaryRoomActionResolver(contexts:"))
        XCTAssertTrue(text.contains("ExclusionReasonLoader.reasons"))
        XCTAssertTrue(text.contains("CoreRoomActions.live"))
    }

    func testStandUpUsesPlacementInstantiateThenOpen() throws {
        let appModelText = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/AppModel.swift"),
            encoding: .utf8
        )
        let standUpText = (try? String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/AppModel+StandUp.swift"),
            encoding: .utf8
        )) ?? ""
        let text = appModelText + "\n" + standUpText
        XCTAssertTrue(text.contains("RoomStandUpClient.instantiate"))
        XCTAssertTrue(text.contains("actions.openRoom"))
        let support = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/RoomSurfaceSupport.swift"),
            encoding: .utf8
        )
        // 바깥 CLI 클라이언트는 RoomSurfaceClients.swift 로 분리(파일 400줄 규칙).
        let clients = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/RoomSurfaceClients.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(clients.contains("RoomStandUpClient"))
        XCTAssertTrue(clients.contains("BinaryLocator.find(\"agent-tenant-isolation-manager\")"))
        XCTAssertFalse(clients.contains("Process()"))
        XCTAssertFalse(support.contains("Process()"))
        XCTAssertFalse(support.contains("NSHomeDirectory"))
        XCTAssertFalse(support.contains("homeDirectoryForCurrentUser"))
        XCTAssertFalse(support.contains("Documents"))
    }

    func testPlanIDPrefersROOMLayoutIdThenFolderName() {
        let folder = URL(
            fileURLWithPath: "/tmp/.tenants/gujo/rooms/PLAN-DIR/seller",
            isDirectory: true
        )
        XCTAssertEqual(planID(folder: folder, layoutId: "from-json"), "from-json")
        XCTAssertEqual(planID(folder: folder, layoutId: ""), "PLAN-DIR")

        let canonicalFolder = URL(
            fileURLWithPath: "/tmp/.tenants/gujo/rooms/ROOM-ID-1",
            isDirectory: true
        )
        XCTAssertEqual(planID(folder: canonicalFolder, layoutId: ""), "")
        XCTAssertEqual(planID(folder: canonicalFolder, layoutId: "from-spec"), "from-spec")
    }

    func testStandingOrScheduledFilter() {
        XCTAssertTrue(isStandingOrScheduled(slug: "command-room", nature: nil))
        XCTAssertTrue(isStandingOrScheduled(slug: "a", nature: ["standing": ["domain": "fleet"]]))
        XCTAssertTrue(isStandingOrScheduled(slug: "b", nature: ["scheduled": ["cron": "0 3 * * *"]]))
        XCTAssertFalse(isStandingOrScheduled(slug: "c", nature: ["oneShot": [:]]))
        XCTAssertFalse(isStandingOrScheduled(slug: "d", nature: nil))
    }

    func testParsesStandingBlueprintsFromRoomListJSON() {
        let stdout = """
        {"ok":true,"payload":[
          {"slug":"fleet-freshness-room",
            "title":"함대",
            "nature":{"standing":{"domain":"fleet"}},
            "task":"신선도",
            "verdict":"true",
            "toolbelt":["agent-lint-catalog"],
            "wallPreset":"toolbelt",
            "walls":{"writePaths":["~/.tenants/**"],
            "network":true},
            "brief":[]},
          {"slug":"one-off",
            "title":"일회",
            "nature":{"oneShot":{}},
            "task":"잠깐",
            "verdict":"true",
            "toolbelt":[],
            "wallPreset":"toolbelt",
            "walls":{"writePaths":[],
            "network":false},
            "brief":[]},
          {"slug":"command-room",
            "title":"지휘실",
            "task":"지휘",
            "verdict":"true",
            "toolbelt":[],
            "wallPreset":"open",
            "walls":{"writePaths":[],
            "network":true},
            "brief":[]}
        ]}
        """
        let picks = standingOrScheduledBlueprints(from: stdout)
        XCTAssertEqual(picks.map(\.slug), ["fleet-freshness-room", "command-room"])
    }

    func testParsesInstantiateRoomID() {
        let stdout = """
        {"ok":true,"command":"placement-instantiate",
          "payload":{"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "tenantID":"tenant:gujo",
          "rooms":[{"id":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "blueprintSlug":"fleet-freshness-room"}]}}
        """
        let plan = standUpPlan(from: stdout, slug: "fleet-freshness-room", tenant: "tenant:gujo")
        XCTAssertEqual(plan?.planID, "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        XCTAssertEqual(plan?.roomID, "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        XCTAssertEqual(plan?.slug, "fleet-freshness-room")
        XCTAssertEqual(plan?.tenant, "tenant:gujo")
    }

    func testParsesComplianceReasonFromIsolationJSON() {
        XCTAssertEqual(
            complianceReason(from: "{\"compliant\":false,\"reason\":\"not installed\",\"method\":\"capabilities\"}"),
            "not installed"
        )
        XCTAssertEqual(
            complianceReason(from: "{\"ok\":true,\"result\":{\"compliant\":false,\"reason\":\"probe miss\"}}"),
            "probe miss"
        )
    }

    func testRoomURLUsesPathResolver() throws {
        let text = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/RoomSurfaceSupport.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("RoomPathResolver.resolveRoomURL"))
        XCTAssertFalse(text.contains("spec.layoutID"))
    }

    func testBriefingHeaderUsesResolver() throws {
        let text = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/RoomBriefingHeaderView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("BriefingFieldsResolver.resolve"))
        XCTAssertFalse(text.contains("room.wallPreset.isEmpty"))
    }

    func testCredentialSectionUsesToolDetector() throws {
        let text = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/RoomDetailView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("ToolAuthReadinessPolicy.evaluate"))
        XCTAssertFalse(text.contains("claude-config"))
    }

    func testWindowHasDefaultSize() throws {
        let text = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/AgentRoomTerminalApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains(".defaultSize"))
    }

    func testMainViewHasMaxFrame() throws {
        let text = try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AgentRoomTerminal/MainView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(text.contains("maxWidth: .infinity"))
        XCTAssertTrue(text.contains("maxHeight: .infinity"))
        XCTAssertTrue(text.contains("idealWidth"))
    }

    func testLocalizationParity() throws {
        let keys = try declaredKeys()
        XCTAssertGreaterThan(keys.count, 20)
        let ko = try strings("ko")
        let en = try strings("en")
        for key in keys {
            XCTAssertNotNil(ko[key], "ko 에 없는 키: \(key)")
            XCTAssertNotNil(en[key], "en 에 없는 키: \(key)")
        }
        XCTAssertEqual(Set(keys), Set(ko.keys), "ko orphan or missing")
        XCTAssertEqual(Set(keys), Set(en.keys), "en orphan or missing")
        XCTAssertEqual(ko["menu.stand_up"], "방 만들기")
        XCTAssertEqual(en["menu.stand_up"], "Create Room")
        let hangul = ko.filter { $0.value.range(of: "\\p{Hangul}", options: .regularExpression) != nil }
        XCTAssertGreaterThan(Double(hangul.count) / Double(ko.count), 0.9)
    }

    func testGUISourcesDoNotWalkHomeDocuments() throws {
        let gui = appRoot.appendingPathComponent("Sources/AgentRoomTerminal")
        let files = try FileManager.default.subpathsOfDirectory(atPath: gui.path)
            .filter { $0.hasSuffix(".swift") }
        for file in files {
            let text = try String(contentsOf: gui.appendingPathComponent(file), encoding: .utf8)
            XCTAssertFalse(text.contains("homeDirectoryForCurrentUser"), file)
            XCTAssertFalse(text.contains("NSHomeDirectory"), file)
            XCTAssertFalse(text.contains("appendingPathComponent(\"Documents\""), file)
        }
    }

    private func strings(_ lang: String) throws -> [String: String] {
        let url = appRoot.appendingPathComponent(
            "Sources/AgentRoomTerminal/Localization/Resources/\(lang).lproj/Localizable.strings"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: "\" = \"")
            guard parts.count == 2 else { continue }
            let key = String(parts[0].dropFirst())
            let value = String(parts[1].dropLast(2))
            out[key] = value
        }
        return out
    }

    private func declaredKeys() throws -> [String] {
        let url = appRoot.appendingPathComponent("Sources/AgentRoomTerminal/Localization/L10n.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n")
            .filter { $0.contains("case ") && $0.contains("= \"") }
            .compactMap { line -> String? in
                let parts = line.components(separatedBy: "\"")
                return parts.count >= 2 ? parts[1] : nil
            }
    }
}

private func planID(folder: URL, layoutId: String) -> String {
    if !layoutId.isEmpty { return layoutId }
    let parentName = folder.deletingLastPathComponent().lastPathComponent
    if parentName != RoomPaths.roomsDirectoryName {
        return parentName
    }
    return ""
}

private func isStandingOrScheduled(slug: String, nature: Any?) -> Bool {
    if slug == "command-room" { return true }
    if let name = nature as? String {
        return name == "standing" || name == "scheduled"
    }
    guard let dict = nature as? [String: Any] else { return false }
    return dict["standing"] != nil || dict["scheduled"] != nil
}

private func objects(from stdout: String) -> [Any] {
    guard let start = stdout.firstIndex(of: "{") ?? stdout.firstIndex(of: "[") else { return [] }
    let blob = String(stdout[start...])
    guard let raw = try? JSONSerialization.jsonObject(with: Data(blob.utf8)) else { return [] }
    if let array = raw as? [Any] { return array }
    guard let dict = raw as? [String: Any] else { return [] }
    if let payload = dict["payload"] {
        if let array = payload as? [Any] { return array }
        if let object = payload as? [String: Any] { return [object] }
    }
    if let result = dict["result"] {
        if let array = result as? [Any] { return array }
        if let object = result as? [String: Any] { return [object] }
    }
    return [dict]
}

private struct Pick {
    var slug: String
}

private func standingOrScheduledBlueprints(from stdout: String) -> [Pick] {
    objects(from: stdout).compactMap { item -> Pick? in
        guard let dict = item as? [String: Any] else { return nil }
        let slug = dict["slug"] as? String ?? ""
        guard !slug.isEmpty, isStandingOrScheduled(slug: slug, nature: dict["nature"]) else {
            return nil
        }
        return Pick(slug: slug)
    }
}

private struct Plan {
    var planID: String
    var roomID: String
    var slug: String
    var tenant: String
}

private func standUpPlan(from stdout: String, slug: String, tenant: String) -> Plan? {
    guard let plan = objects(from: stdout).first as? [String: Any] else { return nil }
    let planID = plan["id"] as? String ?? ""
    let rooms = plan["rooms"] as? [[String: Any]] ?? []
    let first = rooms.first
    let roomID = (first?["id"] as? String) ?? (plan["roomID"] as? String) ?? ""
    let resolvedSlug = (first?["blueprintSlug"] as? String) ?? slug
    let resolvedTenant = (plan["tenantID"] as? String) ?? tenant
    guard !planID.isEmpty, !roomID.isEmpty else { return nil }
    return Plan(planID: planID, roomID: roomID, slug: resolvedSlug, tenant: resolvedTenant)
}

private func complianceReason(from stdout: String) -> String? {
    guard let object = objects(from: stdout).first as? [String: Any] else { return nil }
    if let reason = object["reason"] as? String, !reason.isEmpty { return reason }
    if let nested = object["result"] as? [String: Any],
       let reason = nested["reason"] as? String, !reason.isEmpty {
        return reason
    }
    return nil
}
