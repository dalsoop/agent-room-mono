import Foundation

/// 방·데몬 설정이 공유하는 튜닝 5키. 저장소 구현은 이 프로토콜만 본다.
public protocol TuningReading: AnyObject, Sendable {
    var idleSeconds: Double { get set }
    var ringLines: Int { get set }
    var handoffFactor: Double { get set }
    var replayCount: Int { get set }
    var promoteSuccesses: Int { get set }
}

extension TuningReading {
    public func snapshot() -> RoomTuning {
        RoomTuning(
            idleSeconds: idleSeconds,
            ringLines: ringLines,
            handoffFactor: handoffFactor,
            replayCount: replayCount,
            promoteSuccesses: promoteSuccesses
        )
    }

    public func apply(_ value: RoomTuning) {
        idleSeconds = value.idleSeconds
        ringLines = value.ringLines
        handoffFactor = value.handoffFactor
        replayCount = value.replayCount
        promoteSuccesses = value.promoteSuccesses
    }
}
