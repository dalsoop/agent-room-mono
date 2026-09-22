import Foundation
import StateMirrorKit

/// 상태 미러 게시 지점 — 스캐폴드가 앱 생성 시점에 심는 함대 계약(CLAUDE.md "앱 상태 미러").
///
/// GUI 앱은 핵심 모델 요약을 `~/.swift-app-state/agent-room-worktree.json` 으로 게시해
/// 에이전트·스크립트가 스크린샷 없이 `swift-app-router state agent-room-worktree` 로 읽는다.
/// 스캐폴드는 앱 의미를 지어내지 않는다 — 표준 건강 필드(status/lastError)만 게시하고,
/// 앱 고유 요약 필드와 호출 지점 연결은 앱 소유자가 채운다.
public enum StateMirrorAdoption {
    /// StateMirror 파일 키 — `~/.swift-app-state/agent-room-worktree.json`.
    public static let appName = "agent-room-worktree"

    public struct State: Codable, Sendable {
        public var status: String
        public var lastError: String?
        public var generatedAt: Date
        public var bindCount: Int

        public init(
            status: String,
            lastError: String? = nil,
            generatedAt: Date = Date(),
            bindCount: Int = 0
        ) {
            self.status = status
            self.lastError = lastError
            self.generatedAt = generatedAt
            self.bindCount = bindCount
        }
    }

    /// 모델 상태가 바뀌는 지점(로드 완료·작업 종료 등)에서 호출한다.
    /// status 를 생략하면 lastError 유무에서 함대 표준 파생(StateMirrorHealth.status)이
    /// 내려간다 — catch 에서는 publish(lastError:) 만으로 충분하다.
    public static func publish(status: String? = nil, lastError: String? = nil, bindCount: Int = 0) {
        StateMirror.publish(app: appName, State(
            status: status ?? StateMirrorHealth.status(lastError: lastError),
            lastError: lastError,
            bindCount: bindCount))
    }
}
