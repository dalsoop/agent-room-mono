import Foundation

/// 프레임 p95 가 임계를 넘으면 L2 상한을 1 내리고, 10초 동안 다시 안 넘으면 1씩 복구한다.
public enum DegradePolicy {
    public static let recoveryInterval: TimeInterval = 10
    public static let floorCap = 1
    public static let degradeThresholdMs: Double = 24

    public struct Current: Sendable, Equatable {
        public var liveTerminalCap: Int
        public var lastDegradeAt: Date?
        public var lastAdjustAt: Date?

        public init(
            liveTerminalCap: Int,
            lastDegradeAt: Date? = nil,
            lastAdjustAt: Date? = nil
        ) {
            self.liveTerminalCap = liveTerminalCap
            self.lastDegradeAt = lastDegradeAt
            self.lastAdjustAt = lastAdjustAt
        }
    }

    /// `cap` 은 튜닝 상한. 반환 `cap` 은 다음에 쓸 실효 L2 상한.
    public static func next(
        current: Current,
        cap: Int,
        p95: Double,
        now: Date
    ) -> (cap: Int, degraded: Bool) {
        let ceiling = max(floorCap, cap)
        if p95 > degradeThresholdMs {
            let nextCap = max(floorCap, current.liveTerminalCap - 1)
            return (nextCap, nextCap < current.liveTerminalCap)
        }
        let marker = current.lastAdjustAt ?? current.lastDegradeAt
        guard let marker, now.timeIntervalSince(marker) >= recoveryInterval else {
            return (current.liveTerminalCap, false)
        }
        let recovered = min(ceiling, current.liveTerminalCap + 1)
        return (recovered, false)
    }
}
