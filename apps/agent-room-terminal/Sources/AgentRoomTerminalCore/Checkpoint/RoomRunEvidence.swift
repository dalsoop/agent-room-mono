import Foundation

/// 실행 판정 결과
public enum RunVerdict: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case policyViolated = "policy_violated"
}

/// 방 `runs/<runID>/` 증거 폴더에 보존되는 실행 기록.
public struct RoomRunEvidence: Codable, Equatable, Sendable {
    public var runID: String
    public var roomID: String
    public var startedAt: Date
    public var endedAt: Date
    public var durationMs: Int
    public var argv: [String]
    public var exitCode: Int
    public var verdict: RunVerdict
    public var checkpointIDBefore: String
    public var checkpointIDAfter: String?
    public var rolledBack: Bool
    public var stdoutSummary: String
    public var stderrSummary: String
    public var violations: [String]
    public var passedVerifications: [String]

    public init(
        runID: String,
        roomID: String,
        startedAt: Date = Date(),
        endedAt: Date = Date(),
        durationMs: Int = 0,
        argv: [String] = [],
        exitCode: Int = 0,
        verdict: RunVerdict = .passed,
        checkpointIDBefore: String = "",
        checkpointIDAfter: String? = nil,
        rolledBack: Bool = false,
        stdoutSummary: String = "",
        stderrSummary: String = "",
        violations: [String] = [],
        passedVerifications: [String] = []
    ) {
        self.runID = runID
        self.roomID = roomID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.argv = argv
        self.exitCode = exitCode
        self.verdict = verdict
        self.checkpointIDBefore = checkpointIDBefore
        self.checkpointIDAfter = checkpointIDAfter
        self.rolledBack = rolledBack
        self.stdoutSummary = stdoutSummary
        self.stderrSummary = stderrSummary
        self.violations = violations
        self.passedVerifications = passedVerifications
    }
}
