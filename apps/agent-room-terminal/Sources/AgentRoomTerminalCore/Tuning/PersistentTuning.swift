import Foundation
import os

/// 디스크 저장소(`TuningStore`, `tuning.json`)에 결속된 튜닝 5키.
/// 읽기는 메모리 사본, 쓰기는 저장소에 먼저 기록한 뒤 사본을 갱신한다.
/// GUI 설정 화면과 CLI `tuning show|set` 이 같은 파일을 본다.
public final class PersistentTuning: TuningReading, Sendable {
    private let store: TuningStore
    private let memory: InMemoryTuning

    public init(store: TuningStore) throws {
        self.store = store
        let values = try store.load()
        self.memory = InMemoryTuning(RoomTuning(
            idleSeconds: values.idleSeconds,
            ringLines: values.ringLines,
            handoffFactor: values.handoffFactor,
            replayCount: values.replayCount,
            promoteSuccesses: values.promoteSuccesses
        ))
    }

    public var idleSeconds: Double {
        get { memory.idleSeconds }
        set { persist(.idleSeconds, "\(newValue)") { memory.idleSeconds = newValue } }
    }

    public var ringLines: Int {
        get { memory.ringLines }
        set { persist(.ringLines, "\(newValue)") { memory.ringLines = newValue } }
    }

    public var handoffFactor: Double {
        get { memory.handoffFactor }
        set { persist(.handoffFactor, "\(newValue)") { memory.handoffFactor = newValue } }
    }

    public var replayCount: Int {
        get { memory.replayCount }
        set { persist(.replayCount, "\(newValue)") { memory.replayCount = newValue } }
    }

    public var promoteSuccesses: Int {
        get { memory.promoteSuccesses }
        set { persist(.promoteSuccesses, "\(newValue)") { memory.promoteSuccesses = newValue } }
    }

    /// 저장소 기록이 실패하면 메모리 사본도 바꾸지 않는다 — 화면과 파일이 어긋나지 않게.
    /// 실패는 `lastError` 로 드러낸다(삼키지 않는다).
    public var lastError: String? { errorBox.withLock { $0 } }

    private let errorBox = OSAllocatedUnfairLock<String?>(initialState: nil)

    private func persist(_ key: TuningKey, _ raw: String, then update: () -> Void) {
        do {
            try store.set(key: key.rawValue, value: raw)
            errorBox.withLock { $0 = nil }
            update()
        } catch {
            let message = "\(key.rawValue): \(error.localizedDescription)"
            errorBox.withLock { $0 = message }
        }
    }
}
