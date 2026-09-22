import Foundation
import StateRootKit

/// 세션 기록 루트. 홈을 직접 조립하지 않고 StateRootKit 호스트 경로를 쓴다.
public enum BudgetHostPaths {
    public static func codexSessions(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String
    ) -> URL {
        host(".codex/sessions", environment: environment, homeDirectory: homeDirectory)
    }

    public static func claudeProjects(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String
    ) -> URL {
        host(".claude/projects", environment: environment, homeDirectory: homeDirectory)
    }

    public static func grokSessions(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String
    ) -> URL {
        host(".grok/sessions", environment: environment, homeDirectory: homeDirectory)
    }

    public static func antigravityCLI(
        environment: [String: String] = [:],
        homeDirectory: String
    ) -> URL {
        host(".gemini/antigravity-cli", environment: environment, homeDirectory: homeDirectory)
    }

    public static func antigravitySummaries(
        environment: [String: String] = [:],
        homeDirectory: String
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.hostPath(
                ".gemini/antigravity-cli/conversation_summaries.db",
                environment: environment,
                homeDirectory: homeDirectory
            ),
            isDirectory: false
        )
    }

    static func host(
        _ relative: String,
        environment: [String: String],
        homeDirectory: String
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.hostPath(
                relative,
                environment: environment,
                homeDirectory: homeDirectory
            ),
            isDirectory: true
        )
    }
}

public protocol BudgetClock: Sendable {
    func now() -> Date
}

public struct SystemBudgetClock: BudgetClock {
    public init() {}
    public func now() -> Date { Date() }
}

public protocol HandoffIdentifying: Sendable {
    func nextID() -> String
}

public struct UUIDHandoffIDs: HandoffIdentifying {
    public init() {}
    public func nextID() -> String { UUID().uuidString.lowercased() }
}
