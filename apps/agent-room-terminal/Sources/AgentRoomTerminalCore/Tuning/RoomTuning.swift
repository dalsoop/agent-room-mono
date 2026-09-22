import Foundation

/// 방·데몬 공유 튜닝 5키 값. 읽기/쓰기는 `TuningReading` 경유.
public struct RoomTuning: Sendable, Equatable, Codable {
    public var idleSeconds: Double
    public var ringLines: Int
    public var handoffFactor: Double
    public var replayCount: Int
    public var promoteSuccesses: Int

    public init(
        idleSeconds: Double = 60,
        ringLines: Int = 10_000,
        handoffFactor: Double = 0.8,
        replayCount: Int = 3,
        promoteSuccesses: Int = 5
    ) {
        self.idleSeconds = idleSeconds
        self.ringLines = ringLines
        self.handoffFactor = handoffFactor
        self.replayCount = replayCount
        self.promoteSuccesses = promoteSuccesses
    }

    public static let factory = RoomTuning(
        idleSeconds: 60,
        ringLines: 10_000,
        handoffFactor: 0.8,
        replayCount: 3,
        promoteSuccesses: 5
    )

    public static let fileName = "room-tuning.json"
}
