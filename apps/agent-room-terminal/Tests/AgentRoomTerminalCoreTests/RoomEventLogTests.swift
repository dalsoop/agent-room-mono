import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomEventLog — append-only events.jsonl 원장")
struct RoomEventLogTests {
    @Test("원장 append/read/since/손상 줄 건너뛰기 검증")
    func testAppendReadSinceAndCorruptLines() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-event-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let log = RoomEventLog(roomURL: tempDir)

        // 1. 이벤트 추가 (created, assembled, sessionStarted)
        let ev1 = try log.append(.created())
        #expect(ev1.seq == 1)
        #expect(ev1.kind == RoomEventKind.created)

        let ev2 = try log.append(.assembled())
        #expect(ev2.seq == 2)
        #expect(ev2.kind == RoomEventKind.assembled)

        let ev3 = try log.append(.sessionStarted(sessionID: "sess-1", pid: 1234, tool: "claude"))
        #expect(ev3.seq == 3)
        #expect(ev3.payload["sessionID"]?.string == "sess-1")

        // 2. 파일에 손상 줄 및 빈 줄 주입
        let fileURL = log.fileURL
        let corruptLine = "{\"broken_json\": true, incomplete...\n\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(corruptLine.utf8))
            try handle.close()
        }

        // 3. 추가 이벤트 기록 (occupied)
        let ev4 = try log.append(.occupied(agent: "claude", sessionID: "sess-1"))
        #expect(ev4.seq == 4)

        // 4. 전체 읽기: 손상 줄 1개 건너뛰고 corruptCount == 1, 4개 유효 이벤트
        let fullResult = log.read(since: 0)
        #expect(fullResult.corruptCount == 1)
        #expect(fullResult.events.count == 4)
        #expect(fullResult.events.map(\.seq) == [1, 2, 3, 4])

        // 5. since 읽기 (since: 2)
        let sinceResult = log.read(since: 2)
        #expect(sinceResult.events.count == 2)
        #expect(sinceResult.events.map(\.seq) == [3, 4])

        // 6. tail(2)
        let tail2 = log.tail(2)
        #expect(tail2.count == 2)
        #expect(tail2.map(\.seq) == [3, 4])
    }

    @Test("동시 기록 순서 및 seq 무결성 검증 (flock)")
    func testConcurrentAppendsSequenceIntegrity() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-event-concurrent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let log = RoomEventLog(roomURL: tempDir)
        let count = 30

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    do {
                        _ = try log.append(RoomEvent(kind: "ping-\(i)", payload: ["index": .int(i)]))
                    } catch {
                        Issue.record("append failed: \(error)")
                    }
                }
            }
        }

        let result = log.read(since: 0)
        #expect(result.corruptCount == 0)
        #expect(result.events.count == count)

        let seqs = result.events.map(\.seq)
        let expectedSeqs = Array(1...count)
        #expect(seqs == expectedSeqs)
    }
}
