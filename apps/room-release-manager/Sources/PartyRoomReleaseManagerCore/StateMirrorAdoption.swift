import Foundation
import StateMirrorKit

/// 상태 미러 — 에이전트가 스크린샷 없이 배포 매니저 상태를 읽는다.
public enum StateMirrorAdoption {
    public static let appName = "party-room-release-manager"

    public struct State: Codable, Sendable {
        public var status: String
        public var projectPath: String
        public var artifactsReady: Int
        public var generatedAt: Date

        public init(
            status: String,
            projectPath: String = "",
            artifactsReady: Int = 0,
            generatedAt: Date = Date()
        ) {
            self.status = status
            self.projectPath = projectPath
            self.artifactsReady = artifactsReady
            self.generatedAt = generatedAt
        }
    }

    public static func publish(
        status: String = "ok",
        projectPath: String = "",
        artifactsReady: Int = 0
    ) {
        StateMirror.publish(
            app: appName,
            State(status: status, projectPath: projectPath, artifactsReady: artifactsReady)
        )
    }
}
