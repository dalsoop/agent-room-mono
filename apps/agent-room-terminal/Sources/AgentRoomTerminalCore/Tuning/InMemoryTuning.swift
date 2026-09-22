import Foundation
import os

/// 튜닝 5키 기본 구현. 디스크 저장소(`TuningStore`) 결속은 다른 작업.
public final class InMemoryTuning: TuningReading, Sendable {
    private struct Values: Sendable {
        var idleSeconds: Double
        var ringLines: Int
        var handoffFactor: Double
        var replayCount: Int
        var promoteSuccesses: Int
    }

    private let lock: OSAllocatedUnfairLock<Values>

    public init(_ value: RoomTuning = .factory) {
        lock = OSAllocatedUnfairLock(initialState: Values(
            idleSeconds: value.idleSeconds,
            ringLines: value.ringLines,
            handoffFactor: value.handoffFactor,
            replayCount: value.replayCount,
            promoteSuccesses: value.promoteSuccesses
        ))
    }

    public var idleSeconds: Double {
        get { lock.withLock { $0.idleSeconds } }
        set { lock.withLock { $0.idleSeconds = newValue } }
    }

    public var ringLines: Int {
        get { lock.withLock { $0.ringLines } }
        set { lock.withLock { $0.ringLines = newValue } }
    }

    public var handoffFactor: Double {
        get { lock.withLock { $0.handoffFactor } }
        set { lock.withLock { $0.handoffFactor = newValue } }
    }

    public var replayCount: Int {
        get { lock.withLock { $0.replayCount } }
        set { lock.withLock { $0.replayCount = newValue } }
    }

    public var promoteSuccesses: Int {
        get { lock.withLock { $0.promoteSuccesses } }
        set { lock.withLock { $0.promoteSuccesses = newValue } }
    }
}
