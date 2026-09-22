import Foundation

/// `agent-room-terminal exec --timeout N` — 기본 300초, 상한 3600초.
public enum ExecTimeout: Sendable {
    public static let defaultSeconds = 300
    public static let maxSeconds = 3600

    public enum ParseError: Error, Equatable, Sendable {
        case invalid(String)
    }

    public static func parse(_ raw: String?) throws -> Int {
        guard let raw else { return defaultSeconds }
        guard let value = Int(raw), value > 0 else {
            throw ParseError.invalid(raw)
        }
        return min(value, maxSeconds)
    }

    public static func resolve(_ requested: Int?) -> Int {
        guard let requested, requested > 0 else { return defaultSeconds }
        return min(requested, maxSeconds)
    }
}
