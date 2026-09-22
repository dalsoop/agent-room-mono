import XCTest
@testable import AgentRoomTerminalCore

final class CapabilitiesContractTests: XCTestCase {
    func testEnvelopeFields() throws {
        let caps = CapabilitiesContract.make(
            cliPath: "/tmp/agent-room-terminal",
            sqlitePath: "~/Library/Application Support/net.ranode.agent-room-terminal/app.sqlite",
            freshness: "~/.swift-app-state/agent-room-terminal.json"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(caps)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["name"] as? String, "agent-room-terminal")
        XCTAssertEqual(object["version"] as? String, RoomCLIVersion.current())
        let stateRoot = try XCTUnwrap(object["stateRoot"] as? [String: Any])
        XCTAssertEqual(stateRoot["env"] as? String, "SWIFT_APP_STATE_ROOT")
        let commands = try XCTUnwrap(object["commands"] as? [[String: Any]])
        let names = Set(commands.compactMap { $0["name"] as? String })
        for required in [
            "open", "close", "exec", "smoke", "tree", "snapshot", "check", "budget",
            "handoff", "simulate", "habit", "habit promote", "daemon", "usage",
            "tuning", "capabilities", "version", "open-gui",
        ] {
            XCTAssertTrue(names.contains(required), required)
        }
        XCTAssertEqual(dryRun(commands, "open"), true)
        XCTAssertEqual(dryRun(commands, "close"), true)
        XCTAssertEqual(dryRun(commands, "handoff"), true)
        XCTAssertEqual(dryRun(commands, "habit promote"), true)
        let depends = try XCTUnwrap(object["depends"] as? [[String: Any]])
        let refs = Set(depends.compactMap { $0["ref"] as? String })
        XCTAssertEqual(
            refs,
            ["agent-tenant-isolation-manager", "agent-wiki", "zsh"]
        )
        let kinds = Dictionary(uniqueKeysWithValues: depends.compactMap { item -> (String, String)? in
            guard let ref = item["ref"] as? String, let kind = item["kind"] as? String else {
                return nil
            }
            return (ref, kind)
        })
        XCTAssertEqual(kinds["zsh"], "system")
        XCTAssertEqual(kinds["agent-tenant-isolation-manager"], "cli")
    }

    func testZeroAgentWorkTodoReverseCalls() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AgentRoomTerminalCoreTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Sources", isDirectory: true)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourcesURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            XCTFail("Failed to enumerate Sources directory")
            return
        }

        var occurrences: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            if content.contains("agent-work-todo") {
                occurrences.append(fileURL.path)
            }
        }

        XCTAssertTrue(
            occurrences.isEmpty,
            "R1 violation: found 'agent-work-todo' in Sources files:\n\(occurrences.joined(separator: "\n"))"
        )
    }

    private func dryRun(_ commands: [[String: Any]], _ name: String) -> Bool? {
        commands.first { $0["name"] as? String == name }?["dryRun"] as? Bool
    }
}
