import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class HandoffEvidenceTests: XCTestCase {
    var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("handoff-evidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try FileManager.default.removeItem(at: scratch)
        }
        try super.tearDownWithError()
    }

    func testFixtureTranscriptFillsReadDocumentsAndRedactsToken() throws {
        let room = try makeRoom()
        let docA = room.appendingPathComponent("docs/a.md").path
        let docB = room.appendingPathComponent("docs/b.md").path
        try writeClaudeTranscript(in: room, lines: [
            assistantToolUse(
                name: "Read",
                input: #"{"file_path":\#(jsonString(docA))}"#
            ),
            assistantToolUse(
                name: "Read",
                input: #"{"file_path":\#(jsonString(docB))}"#
            ),
            assistantToolUse(name: "Bash", input: #"{"command":"ls work"}"#),
            assistantToolUse(
                name: "Bash",
                input: #"{"command":"curl --token abc https://example.test"}"#
            ),
            assistantToolUse(name: "Bash", input: #"{"command":"git status"}"#),
            assistantText("표 10행을 만들었다. doctor JSON 은 이미 읽었다."),
        ])

        let evidence = HandoffTranscriptMiner.collect(roomURL: room, tool: .claude)
        XCTAssertEqual(evidence.evidenceSource, "transcript")
        XCTAssertEqual(evidence.readDocuments, ["docs/a.md", "docs/b.md"])
        XCTAssertEqual(evidence.executedCommands.count, 3)
        XCTAssertEqual(evidence.executedCommands[0], "ls work")
        XCTAssertEqual(
            evidence.executedCommands[1],
            "curl --token *** https://example.test"
        )
        XCTAssertFalse(evidence.executedCommands[1].contains("abc"))
        XCTAssertEqual(evidence.executedCommands[2], "git status")
        XCTAssertTrue(evidence.lastAssistantText.contains("표 10행"))
    }

    func testMissingTranscriptSetsEvidenceSourceNone() throws {
        let room = try makeRoom()
        let evidence = HandoffTranscriptMiner.collect(roomURL: room, tool: .claude)
        XCTAssertEqual(evidence.evidenceSource, "none")
        XCTAssertEqual(evidence.readDocuments, [])
        XCTAssertEqual(evidence.executedCommands, [])
        XCTAssertEqual(evidence.producedFiles, [])
        XCTAssertEqual(evidence.lastAssistantText, "")
    }

    func testHandoffServiceWritesEvidenceIntoBottleJSON() async throws {
        let room = try makeRoom()
        try writeClaudeTranscript(in: room, lines: [
            assistantToolUse(
                name: "Read",
                input: #"{"file_path":\#(jsonString(room.appendingPathComponent("a.txt").path))}"#
            ),
            assistantToolUse(
                name: "Read",
                input: #"{"file_path":\#(jsonString(room.appendingPathComponent("b.txt").path))}"#
            ),
            assistantToolUse(name: "Bash", input: #"{"command":"pwd"}"#),
            assistantToolUse(
                name: "Bash",
                input: #"{"command":"curl --token abc https://example.test"}"#
            ),
            assistantToolUse(name: "Bash", input: #"{"command":"date"}"#),
        ])
        let service = HandoffService(
            ledger: RecordingHandoffLedger(),
            daemon: FixedSnapshot(lines: ["ok"]),
            ids: QueueIDs(["ev-bottle"]),
            clock: FrozenClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let bottle = try await service.handoff(request(room: room))
        XCTAssertEqual(bottle.readDocuments.count, 2)
        XCTAssertEqual(bottle.executedCommands.count, 3)
        XCTAssertTrue(bottle.executedCommands.contains {
            $0.contains("***") && !$0.contains("abc")
        })
        XCTAssertEqual(bottle.evidenceSource, "transcript")
        let data = try Data(contentsOf: HandoffFolder.file(in: room, id: bottle.id))
        let loaded = try HandoffJSON.decoder().decode(HandoffBottle.self, from: data)
        XCTAssertEqual(loaded.readDocuments, bottle.readDocuments)
        XCTAssertEqual(loaded.executedCommands, bottle.executedCommands)
        XCTAssertEqual(loaded.evidenceSource, "transcript")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object["readDocuments"])
        XCTAssertNotNil(object["executedCommands"])
        XCTAssertNotNil(object["producedFiles"])
        XCTAssertNotNil(object["lastAssistantText"])
        XCTAssertNotNil(object["evidenceSource"])
    }

    func testHandoffServiceWithoutTranscriptWritesNone() async throws {
        let room = try makeRoom()
        let service = HandoffService(
            ledger: RecordingHandoffLedger(),
            daemon: FixedSnapshot(lines: ["ok"]),
            ids: QueueIDs(["none-bottle"]),
            clock: FrozenClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        )
        let bottle = try await service.handoff(request(room: room))
        XCTAssertEqual(bottle.evidenceSource, "none")
        XCTAssertEqual(bottle.readDocuments, [])
        XCTAssertEqual(bottle.executedCommands, [])
    }

    func testOldBottleJSONDecodesWithoutEvidenceFields() throws {
        let json = """
        {
          "id": "old",
          "roomID": "r1",
          "tool": "claude",
          "note": "n",
          "remainingWork": "",
          "rationale": "",
          "habitNotes": [],
          "terminalSnapshot": [],
          "budget": {
            "window": 1,
            "trigger": 0,
            "initialInput": 0,
            "reservedOutput": 0,
            "usable": 1,
            "handoffAt": 1,
            "state": "ok"
          },
          "createdAt": "2026-09-04T00:00:00Z"
        }
        """
        let bottle = try JSONDecoder().decode(HandoffBottle.self, from: Data(json.utf8))
        XCTAssertEqual(bottle.readDocuments, [])
        XCTAssertEqual(bottle.executedCommands, [])
        XCTAssertEqual(bottle.producedFiles, [])
        XCTAssertEqual(bottle.lastAssistantText, "")
        XCTAssertEqual(bottle.evidenceSource, "none")
    }

    func testMarkdownSummaryOrder() {
        var bottle = HandoffBottle(
            id: "b",
            roomID: "r",
            predecessor: nil,
            tool: "claude",
            note: "fallback",
            budget: HandoffDigest.emptyBudget,
            createdAt: "t"
        )
        bottle.pitfalls = ["함정1"]
        bottle.habitCandidates = [
            HabitCandidate(
                ts: "t",
                argv: ["ls"],
                exitCode: 0,
                durationMs: 1,
                tool: "claude"
            )
        ]
        bottle.evidence = HandoffSessionEvidence(
            readDocuments: ["docs/a.md"],
            executedCommands: ["git status"],
            producedFiles: ["work/out.json"],
            lastAssistantText: "결론 본문",
            evidenceSource: "transcript"
        )
        let md = bottle.markdownSummary()
        let conclusion = md.range(of: "## 결론")
        let docs = md.range(of: "## 읽은 문서")
        let files = md.range(of: "## 만든 파일")
        let cmds = md.range(of: "## 실행한 명령")
        let pits = md.range(of: "## 함정")
        let habits = md.range(of: "## 습관 후보")
        XCTAssertNotNil(conclusion)
        XCTAssertNotNil(docs)
        XCTAssertNotNil(files)
        XCTAssertNotNil(cmds)
        XCTAssertNotNil(pits)
        XCTAssertNotNil(habits)
        XCTAssertTrue(conclusion!.lowerBound < docs!.lowerBound)
        XCTAssertTrue(docs!.lowerBound < files!.lowerBound)
        XCTAssertTrue(files!.lowerBound < cmds!.lowerBound)
        XCTAssertTrue(cmds!.lowerBound < pits!.lowerBound)
        XCTAssertTrue(pits!.lowerBound < habits!.lowerBound)
        XCTAssertTrue(md.contains("결론 본문"))
        XCTAssertTrue(md.contains("docs/a.md"))
        XCTAssertTrue(md.contains("work/out.json"))
        XCTAssertTrue(md.contains("git status"))
        XCTAssertTrue(md.contains("함정1"))
        XCTAssertTrue(md.contains("ls"))
    }

    func testOutsideRoomTranscriptPathIsIgnored() throws {
        let room = try makeRoom()
        let outsider = scratch.appendingPathComponent("outside.jsonl")
        try Data("{}\n".utf8).write(to: outsider)
        try TranscriptRegistry.register(
            roomURL: room,
            tool: .claude,
            path: outsider.path
        )
        let evidence = HandoffTranscriptMiner.collect(roomURL: room, tool: .claude)
        XCTAssertEqual(evidence.evidenceSource, "none")
    }

    func testRedactAuthorizationAndKeyEquals() {
        let auth = HandoffTranscriptMiner.redactSecrets(
            "curl -H Authorization:Bearer xyz"
        )
        XCTAssertEqual(auth, "curl -H Authorization: ***")
        let key = HandoffTranscriptMiner.redactSecrets("export key=secret")
        XCTAssertEqual(key, "export key=***")
    }

    private func makeRoom() throws -> URL {
        let url = scratch.appendingPathComponent("room", isDirectory: true)
        try RoomDirectoryLayout.create(at: url)
        try Data(#"{"id":"room-ev"}"#.utf8).write(
            to: url.appendingPathComponent("ROOM.json")
        )
        return url
    }

    private func writeClaudeTranscript(in room: URL, lines: [String]) throws {
        let config = AgentCredentialInjector.configDirName(tool: .claude, roomURL: room)
        let dirPath = TranscriptLocations.claudeProjectDirectory(
            cwd: room.path,
            configDirectory: config.path
        )
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = lines.joined(separator: "\n") + "\n"
        try Data(body.utf8).write(to: dir.appendingPathComponent("session.jsonl"))
    }

    private func assistantToolUse(name: String, input: String) -> String {
        """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"\(name)","input":\(input)}]}}
        """
    }

    private func assistantText(_ text: String) -> String {
        let payload = jsonString(text)
        return """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":\(payload)}]}}
        """
    }

    private func jsonString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func request(room: URL) -> HandoffRequest {
        HandoffRequest(
            roomID: "room-ev",
            roomURL: room,
            planID: "plan",
            note: "끊는다",
            predecessor: nil,
            parentRoomURL: nil,
            tool: .claude,
            budget: Budget.compute(
                tool: .claude, initialInput: 0, used: 10,
                elapsedMinutes: 1, estimatedWorkMinutes: 60
            ),
            occupant: "a",
            successorOccupant: "b",
            successorHandle: "b",
            sessionID: "s",
            wallMode: "full",
            authority: .commandRoom(sessionID: "s", seatedRoomID: "room-ev")
        )
    }
}
