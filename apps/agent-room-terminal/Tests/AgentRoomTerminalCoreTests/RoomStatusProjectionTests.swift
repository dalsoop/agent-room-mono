import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomStatusProjection — 이벤트 스트림 상태 투영 순수 함수")
struct RoomStatusProjectionTests {
    @Test("빈 이벤트 목록은 created 상태")
    func testEmptyEvents() {
        let status = RoomStatusProjection.reduce(events: [])
        #expect(status.phase == .created)
        #expect(status.sessionID == nil)
        #expect(status.occupant == nil)
        #expect(status.exitCode == nil)
    }

    @Test("생성 -> 조립 -> 세션시작 -> 착석 -> 판정 -> 종료 -> 닫힘 라이프사이클 투영")
    func testLifecycleProjection() {
        var events: [RoomEvent] = []

        // 1. created
        events.append(RoomEvent(seq: 1, kind: RoomEventKind.created))
        var status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .created)

        // 2. assembled
        events.append(RoomEvent(seq: 2, kind: RoomEventKind.assembled))
        status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .open)

        // 3. sessionStarted
        events.append(RoomEvent.sessionStarted(sessionID: "sess-abc", pid: 4567, tool: "claude"))
        events[2].seq = 3
        status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .open)
        #expect(status.sessionID == "sess-abc")

        // 4. occupied
        events.append(RoomEvent.occupied(agent: "agent:codex", sessionID: "sess-abc"))
        events[3].seq = 4
        status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .occupied)
        #expect(status.occupant == "agent:codex")
        #expect(status.sessionID == "sess-abc")

        // 5. verdictRan
        events.append(RoomEvent.verdictRan(exit: 0, summary: "all passed"))
        events[4].seq = 5
        status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .occupied)
        #expect(status.exitCode == 0)

        // 6. sessionExited
        events.append(RoomEvent.sessionExited(code: 0, sessionID: "sess-abc"))
        events[5].seq = 6
        status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .exited)
        #expect(status.exitCode == 0)

        // 7. closed
        events.append(RoomEvent.closed(sessionID: "sess-abc"))
        events[6].seq = 7
        status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .closed)
    }

    @Test("vacated 이벤트 시 상태가 open 으로 복원되고 occupant 는 비워진다")
    func testVacatedProjection() {
        let events = [
            RoomEvent(seq: 1, kind: RoomEventKind.assembled),
            RoomEvent.occupied(agent: "agent:codex", sessionID: "s-1"),
            RoomEvent.vacated(reason: "handoff completed"),
        ]
        let status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .open)
        #expect(status.occupant == nil)
    }
}
