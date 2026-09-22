import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite struct RoomResultResolverTests {

    private func makeFixtures() throws -> (roomDir: URL, workdir: URL, cleanup: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rr-test-\(UUID().uuidString)")
        let roomDir = tmp.appendingPathComponent("room", isDirectory: true)
        let workdir = tmp.appendingPathComponent("work", isDirectory: true)
        let rf2Dir = workdir.appendingPathComponent(".rf2", isDirectory: true)
        try FileManager.default.createDirectory(at: roomDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rf2Dir, withIntermediateDirectories: true)
        return (roomDir, workdir, tmp)
    }

    private func resultJSON(status: String = "done", notes: String = "완료", commits: Int = 2) -> Data {
        let commitsArray = (0..<commits).map { "\"c\($0)\"" }.joined(separator: ",")
        return Data("""
        {"task":"W6","status":"\(status)","commits":[\(commitsArray)],"testExit":0,"notes":"\(notes)"}
        """.utf8)
    }

    private func eventsJSONL(verdict: Int? = nil) -> Data {
        var lines: [String] = [
            """
            {"seq":1,"at":"2026-09-06T09:00:00Z","kind":"occupied","actor":"system","payload":{"agent":"agent:claude@macbook","sessionID":"s1"}}
            """
        ]
        if let exit = verdict {
            lines.append("""
            {"seq":2,"at":"2026-09-06T10:00:00Z","kind":"verdictRan","actor":"daemon","payload":{"exit":\(exit),"summary":"test"}}
            """)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    // (c) statusBadge 계산

    @Test func statusBadgeDone() {
        let fields = RoomResultFields(resultStatus: "done")
        #expect(fields.statusBadge == .done)
    }

    @Test func statusBadgePartial() {
        let fields = RoomResultFields(resultStatus: "partial")
        #expect(fields.statusBadge == .partial)
    }

    @Test func statusBadgeBlocked() {
        let fields = RoomResultFields(resultStatus: "blocked")
        #expect(fields.statusBadge == .blocked)
    }

    @Test func statusBadgeNone() {
        let fields = RoomResultFields()
        #expect(fields.statusBadge == .none)
    }

    // 전체 경로

    @Test func resolveWithAllData() throws {
        let (roomDir, workdir, tmp) = try makeFixtures()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try eventsJSONL(verdict: 0).write(to: roomDir.appendingPathComponent("events.jsonl"))
        try resultJSON().write(to: workdir
            .appendingPathComponent(".rf2", isDirectory: true)
            .appendingPathComponent("result.json"))
        try Data("log output".utf8).write(to: roomDir.appendingPathComponent("launch.log"))

        let fields = RoomResultResolver.resolve(
            roomID: "test",
            roomDirectoryResolver: { _ in roomDir },
            workdirResolver: { _ in workdir.path },
            fileReader: { url in try? Data(contentsOf: url) }
        )

        #expect(fields.resultStatus == "done")
        #expect(fields.resultNotes == "완료")
        #expect(fields.resultCommitCount == 2)
        #expect(fields.ledgerPhase == "occupied")
        #expect(fields.lastVerdictExit == 0)
        #expect(fields.launchLogPath != nil)
    }

    // result.json 없음

    @Test func resolveWithoutResult() throws {
        let fields = RoomResultResolver.resolve(
            roomID: "test",
            roomDirectoryResolver: { _ in nil },
            workdirResolver: { _ in nil },
            fileReader: { _ in nil }
        )

        #expect(fields.resultStatus == nil)
        #expect(fields.statusBadge == .none)
        #expect(!fields.hasResult)
    }

    // phase 계산

    @Test func resolveLedgerPhase() throws {
        let (roomDir, _, tmp) = try makeFixtures()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try eventsJSONL().write(to: roomDir.appendingPathComponent("events.jsonl"))

        let fields = RoomResultResolver.resolve(
            roomID: "test",
            roomDirectoryResolver: { _ in roomDir },
            workdirResolver: { _ in nil },
            fileReader: { url in try? Data(contentsOf: url) }
        )

        #expect(fields.ledgerPhase == "occupied")
    }
}
