import Foundation
import os

public protocol DaemonClock: Sendable {
    func now() -> Date
}

public struct SystemDaemonClock: DaemonClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// Test clock. Advance to trip idle without waiting wall time.
public final class ManualDaemonClock: DaemonClock, Sendable {
    private let instant: OSAllocatedUnfairLock<Date>

    public init(now: Date = Date()) {
        self.instant = OSAllocatedUnfairLock(initialState: now)
    }

    public func now() -> Date {
        instant.withLock { $0 }
    }

    public func advance(_ interval: TimeInterval) {
        instant.withLock { $0 += interval }
    }
}
