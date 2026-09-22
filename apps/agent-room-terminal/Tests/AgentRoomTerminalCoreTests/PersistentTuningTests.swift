import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("PersistentTuning — 디스크 저장소 결속")
struct PersistentTuningTests {
    private func temporaryStore() -> TuningStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-room-terminal-tuning-\(UUID().uuidString)", isDirectory: true)
        return TuningStore(fileURL: dir.appendingPathComponent("tuning.json"))
    }

    @Test("설정한 값이 파일에 남고 새 인스턴스가 같은 값을 읽는다")
    func roundTrip() throws {
        let store = temporaryStore()
        let first = try PersistentTuning(store: store)
        #expect(first.replayCount == TuningValues.default.replayCount)

        first.replayCount = 7
        first.handoffFactor = 0.5
        #expect(first.lastError == nil)

        let second = try PersistentTuning(store: store)
        #expect(second.replayCount == 7)
        #expect(second.handoffFactor == 0.5)
        #expect(try store.load().replayCount == 7)
    }

    @Test("저장 실패 시 메모리 값을 바꾸지 않고 오류를 드러낸다")
    func writeFailureKeepsMemory() throws {
        let blocked = TuningStore(fileURL: URL(fileURLWithPath: "/dev/null/impossible/tuning.json"))
        let tuning = try PersistentTuning(store: blocked)
        let before = tuning.ringLines
        tuning.ringLines = 42
        #expect(tuning.ringLines == before)
        #expect(tuning.lastError != nil)
    }
}
