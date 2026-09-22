import Foundation
import os
import Testing
@testable import AgentRoomTerminalCore

@Suite("TranscriptLocations · SessionAttach")
struct SessionAttachTests {
    @Test("결속에 transcript.path 가 있으면 규칙보다 우선한다")
    func seatPathBeatsRule() throws {
        let root = try makeRoot("seat-priority")
        let sessionID = "sess-seat-1"
        let workdir = "/tmp/measured-cwd"
        let seatPath = root.appendingPathComponent("from-seat.jsonl").path
        try Data("{}\n".utf8).write(to: URL(fileURLWithPath: seatPath))
        try writeGrokFixture(home: root, cwd: workdir, sessionID: sessionID)
        let seat = try writeSeat(
            root: root,
            sessionID: sessionID,
            tool: "grok",
            workdir: workdir,
            transcriptPath: seatPath,
            roomID: UUID()
        )
        let binding = TranscriptLocations.resolve(
            tool: .grok,
            sessionID: sessionID,
            workdir: workdir,
            homeDirectory: root.path,
            environment: [:],
            files: FoundationRoomFileIO(),
            seat: seat
        )
        #expect(binding.reason == TranscriptBindingReason.resolved)
        #expect(binding.path == seatPath)
    }

    @Test("codex 세션 전사 규칙이 실측 픽스처를 푼다 (없으면 noRule 이 남는다)")
    func codexRule() throws {
        let root = try makeRoot("codex-rule")
        let sessionID = "01a08751-be8b-7722-a630-58b769b0b2a5"
        let cwd = "/tmp/codex-cwd"
        let files = FoundationRoomFileIO()
        let missing = CodexTranscriptRule.resolve(
            sessionID: sessionID,
            workdir: cwd,
            homeDirectory: root.path,
            environment: [:],
            files: files
        )
        #expect(missing.reason == TranscriptBindingReason.noRule)
        #expect(missing.path.isEmpty)
        let expected = try writeCodexFixture(home: root, cwd: cwd, sessionID: sessionID)
        let found = CodexTranscriptRule.resolve(
            sessionID: sessionID,
            workdir: cwd,
            homeDirectory: root.path,
            environment: [:],
            files: files
        )
        #expect(found.reason == TranscriptBindingReason.resolved)
        #expect(found.path == expected)
    }

    @Test("grok 세션 전사 규칙이 실측 픽스처를 푼다 (없으면 noRule 이 남는다)")
    func grokRule() throws {
        let root = try makeRoot("grok-rule")
        let sessionID = "01a0875c-3b54-7c93-9597-99250203318e"
        let cwd = "/tmp/grok-cwd"
        let files = FoundationRoomFileIO()
        let missing = GrokTranscriptRule.resolve(
            sessionID: sessionID,
            workdir: cwd,
            homeDirectory: root.path,
            environment: [:],
            files: files
        )
        #expect(missing.reason == TranscriptBindingReason.noRule)
        let expected = try writeGrokFixture(home: root, cwd: cwd, sessionID: sessionID)
        let found = GrokTranscriptRule.resolve(
            sessionID: sessionID,
            workdir: cwd,
            homeDirectory: root.path,
            environment: [:],
            files: files
        )
        #expect(found.reason == TranscriptBindingReason.resolved)
        #expect(found.path == expected)
    }

    @Test("unknown 예산에는 항상 이유가 있다")
    func unknownBudgetHasReason() {
        let files = FoundationRoomFileIO()
        let none = TranscriptBudgetPresence.usage(
            bindings: [], used: nil, handoffAt: 10, files: files
        )
        #expect(none.isUnknown)
        #expect(none.unknownReason == UnknownBudgetReason.noBinding)
        let missingFile = TranscriptBudgetPresence.usage(
            bindings: [TranscriptBinding(tool: "claude", path: "/no/such/transcript.jsonl")],
            used: nil,
            handoffAt: 10,
            files: files
        )
        #expect(missingFile.unknownReason == UnknownBudgetReason.noTranscript)
        let unsupported = TranscriptBudgetPresence.usage(
            bindings: [TranscriptBinding(tool: "other", path: "", reason: TranscriptBindingReason.toolUnsupported)],
            used: nil,
            handoffAt: 10,
            files: files
        )
        #expect(unsupported.unknownReason == UnknownBudgetReason.toolUnsupported)
        let fallback = RoomUsage(used: nil, handoffAt: 0)
        #expect(!(fallback.unknownReason ?? "").isEmpty)
    }

    @Test("attach-session 은 PTY 를 만들지 않는다")
    func attachDoesNotCreatePty() throws {
        let root = try makeRoot("attach-pty")
        let roomID = UUID()
        let sessionID = "sess-pty"
        try writeRoom(root: root, roomID: roomID)
        let ptyCount = OSAllocatedUnfairLock(initialState: 0)
        let hooks = SessionAttachHooks(openPty: {
            ptyCount.withLock { $0 += 1 }
            return "pty-session"
        })
        _ = try SessionAttach.run(SessionAttachRequest(
            sessionID: sessionID,
            roomID: roomID.uuidString,
            environment: ["SWIFT_APP_STATE_ROOT": root.path, "HOME": root.path],
            homeDirectory: root.path,
            hooks: hooks
        ))
        #expect(ptyCount.withLock { $0 } == 0)
    }

    @Test("attach-session 은 attached 사건과 transcripts.json 등록을 남긴다")
    func attachWritesEventAndRegistry() throws {
        let root = try makeRoot("attach-event")
        let roomID = UUID()
        let sessionID = "sess-event"
        let cwd = "/tmp/attach-cwd"
        let transcriptPath = try writeGrokFixture(home: root, cwd: cwd, sessionID: sessionID)
        _ = try writeSeat(
            root: root,
            sessionID: sessionID,
            tool: "grok",
            workdir: cwd,
            transcriptPath: transcriptPath,
            roomID: roomID
        )
        try writeRoom(root: root, roomID: roomID)
        let result = try SessionAttach.run(SessionAttachRequest(
            sessionID: sessionID,
            environment: [
                "SWIFT_APP_STATE_ROOT": root.path,
                "HOME": root.path,
                SeatTranscriptStore.directoryEnv: SeatTranscriptStore.directory(
                    environment: [:], homeDirectory: root.path
                ).path,
            ],
            homeDirectory: root.path
        ))
        let roomURL = try #require(try RoomFolderLocator.find(
            roomID: roomID.uuidString,
            environment: ["SWIFT_APP_STATE_ROOT": root.path]
        ))
        let events = RoomEventLog(roomURL: roomURL).read(since: 0).events
        #expect(events.contains { $0.kind == "attached" })
        let bindings = try TranscriptRegistry.load(in: roomURL)
        #expect(bindings.contains { $0.path == transcriptPath && $0.tool == "grok" })
        #expect(result.sessionID == sessionID)
    }

    @Test("attach-session 결과의 enforcement 값은 실제 집행 범위를 말한다")
    func attachEnforcementIsHonest() throws {
        let root = try makeRoot("attach-enforcement")
        let roomID = UUID()
        let sessionID = "sess-enf"
        try writeRoom(root: root, roomID: roomID)
        let result = try SessionAttach.run(SessionAttachRequest(
            sessionID: sessionID,
            roomID: roomID.uuidString,
            environment: ["SWIFT_APP_STATE_ROOT": root.path, "HOME": root.path],
            homeDirectory: root.path
        ))
        #expect(result.enforcement == WallEnforcementScope.wallsRegisteredOnly)
        #expect(result.wallMode == WallEnforcementScope.wallModeFull)
        let roomURL = try #require(try RoomFolderLocator.find(
            roomID: roomID.uuidString,
            environment: ["SWIFT_APP_STATE_ROOT": root.path]
        ))
        let url = roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent(WallEnforcementScope.fileName)
        let data = try Data(contentsOf: url)
        let record = try JSONDecoder().decode(WallEnforcementRecord.self, from: data)
        #expect(record.enforcement == WallEnforcementScope.wallsRegisteredOnly)
    }

    private func makeRoot(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("art-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeGrokFixture(home: URL, cwd: String, sessionID: String) throws -> String {
        let encoded = GrokTranscriptRule.percentEncode(cwd)
        let file = home
            .appendingPathComponent(".grok/sessions/\(encoded)/\(sessionID)/updates.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"usage\":{}}\n".utf8).write(to: file)
        return file.path
    }

    @discardableResult
    private func writeCodexFixture(home: URL, cwd: String, sessionID: String) throws -> String {
        let file = home.appendingPathComponent(
            ".codex/sessions/2026/09/10/rollout-2026-09-10T02-57-56-\(sessionID).jsonl"
        )
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let meta = """
        {"type":"session_meta","payload":{"session_id":"\(sessionID)","cwd":"\(cwd)"}}
        """
        try Data((meta + "\n").utf8).write(to: file)
        return file.path
    }

    private func writeSeat(
        root: URL,
        sessionID: String,
        tool: String,
        workdir: String,
        transcriptPath: String,
        roomID: UUID
    ) throws -> SeatTranscriptRecord {
        let dir = SeatTranscriptStore.directory(environment: [:], homeDirectory: root.path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {
          "boundAt": "2026-09-10T00:00:00Z",
          "heartbeatAt": "2026-09-10T00:00:00Z",
          "host": {"paneID": "w1:p1", "pid": 1, "terminalID": "", "workdir": "\(workdir)"},
          "identity": "agent:\(tool)@host",
          "seat": {"planID": "00000000-0000-0000-0000-000000000001", "roomID": "\(roomID.uuidString)", "slug": "command-room"},
          "session": {"id": "\(sessionID)", "provisional": false, "tool": "\(tool)"},
          "transcript": {"path": "\(transcriptPath)", "reason": "resolved"},
          "wall": {"mode": "hookOnly"}
        }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("\(sessionID).json"))
        return try JSONDecoder().decode(
            SeatTranscriptRecord.self,
            from: Data(json.utf8)
        )
    }

    private func writeRoom(root: URL, roomID: UUID) throws {
        let folder = root.appendingPathComponent(
            ".tenants/gujo/rooms/\(roomID.uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document: [String: Any] = [
            "id": roomID.uuidString,
            "slug": "seller",
            "tenant": "tenant:gujo",
            "layoutId": "L1",
            "parentRoomID": "",
            "preset": "toolbelt",
            "task": "일",
            "verdict": "true",
            "brief": [],
            "toolbelt": ["ls"],
            "walls": ["network": true, "writePaths": ["work/**"]],
            "budget": [
                "window": 10, "trigger": 0.8, "initialInput": 0, "reservedOutput": 0,
                "usable": 8, "handoffAt": 6,
            ],
            "excludedTools": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: document)
        try data.write(to: folder.appendingPathComponent("ROOM.json"))
    }
}
