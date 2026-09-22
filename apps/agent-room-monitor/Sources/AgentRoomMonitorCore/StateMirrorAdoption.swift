import Foundation
import StateMirrorKit

/// 상태 미러 게시 지점 — 스캐폴드가 앱 생성 시점에 심는 함대 계약(CLAUDE.md "앱 상태 미러").
///
/// GUI 앱은 핵심 모델 요약을 `~/.swift-app-state/agent-room-monitor.json` 으로 게시해
/// 에이전트·스크립트가 스크린샷 없이 `swift-app-router state agent-room-monitor` 로 읽는다.
/// 스캐폴드는 앱 의미를 지어내지 않는다 — 최소 필드(status/generatedAt)만 게시하고,
/// 앱 고유 요약 필드와 호출 지점 연결은 앱 소유자가 채운다.
public enum StateMirrorAdoption {
    /// StateMirror 파일 키 — `~/.swift-app-state/agent-room-monitor.json`.
    public static let appName = "agent-room-monitor"

    public struct State: Codable, Sendable {
        public var status: String
        public var generatedAt: Date
        public var rooms: Int
        public var blocked: Int
        public var gates: Int
        public var skills: Int
        public var sessions: Int

        public init(
            status: String,
            generatedAt: Date = Date(),
            rooms: Int = 0,
            blocked: Int = 0,
            gates: Int = 0,
            skills: Int = 0,
            sessions: Int = 0
        ) {
            self.status = status
            self.generatedAt = generatedAt
            self.rooms = rooms
            self.blocked = blocked
            self.gates = gates
            self.skills = skills
            self.sessions = sessions
        }
    }

    /// 모델 상태가 바뀌는 지점(로드 완료·작업 종료 등)에서 호출한다.
    public static func publish(_ state: State) {
        StateMirror.publish(app: appName, state)
    }

    public static func publish(status: String = "ok") {
        StateMirror.publish(app: appName, State(status: status))
    }

    /// TwinSnapshot 조립 결과로 상태 미러를 채운다 — rooms·blocked·gates·skills·sessions.
    public static func publish(snapshot: TwinSnapshot) {
        func countRooms(_ node: TwinNode) -> (rooms: Int, blocked: Int, gates: Int) {
            var rooms = 0
            var blocked = 0
            var gates = 0
            if node.icon == "🚪" { rooms += 1 }
            if node.state == .block { blocked += 1 }
            if node.state == .gate { gates += 1 }
            for child in node.children {
                let sub = countRooms(child)
                rooms += sub.rooms
                blocked += sub.blocked
                gates += sub.gates
            }
            return (rooms, blocked, gates)
        }
        let agg = countRooms(snapshot.root)
        let skills = snapshot.root.children.first(where: { $0.id == "skill-warehouse" })?.children.count ?? 0
        let sessions = snapshot.root.children.first(where: { $0.id == "sessions" })
        let sessionsExec = sessions?.state == .exec ? 1 : 0
        StateMirror.publish(
            app: appName,
            State(
                status: snapshot.root.health.notes.isEmpty ? "ok" : "partial",
                rooms: agg.rooms,
                blocked: agg.blocked,
                gates: agg.gates,
                skills: skills,
                sessions: sessionsExec
            )
        )
    }
}
