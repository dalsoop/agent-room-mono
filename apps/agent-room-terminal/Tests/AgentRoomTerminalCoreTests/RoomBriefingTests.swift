import Foundation
import Testing
@testable import AgentRoomTerminalCore

private struct AllowAll: ComplianceChecking, Sendable {
    func isCompliant(cli: String) throws -> Bool { true }
}

@Suite("RoomBriefing — 터미널 첫 화면 4줄 안내문")
struct RoomBriefingTests {
    @Test("4개 항목 줄과 마지막 exit 안내 줄이 올바른 순서로 출력된다")
    func testBriefingTextLines() {
        let text = RoomBriefing.text(
            task: "작업 요약 한 문장",
            verdict: "swift test --filter Smoke",
            writePaths: ["Sources", "Tests"],
            toolbelt: ["git", "swift"]
        )
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 5)
        #expect(lines[0] == "작업: 작업 요약 한 문장")
        #expect(lines[1] == "완료 조건: swift test --filter Smoke")
        #expect(lines[2] == "쓰기 가능: Sources, Tests")
        #expect(lines[3] == "도구: git, swift")
        #expect(lines[4] == "종료하려면 exit 를 입력하세요")
    }

    @Test("RoomAssemblySpec 으로부터 4줄 안내문을 올바르게 생성한다")
    func testBriefingFromSpec() {
        let spec = RoomAssemblySpec(
            roomID: "room-brief-test",
            slug: "brief-slug",
            tenantSlug: "gujo",
            layoutID: "layout-test",
            blueprint: RoomBlueprintSnapshot(
                task: "스펙 기반 작업",
                verdict: "echo ok",
                toolbelt: ["cat", "ls"],
                walls: RoomWallSnapshot(writePaths: ["output/"])
            ),
            tenantPolicy: RoomTenantPolicy(stateRoot: "/tmp", wikiWorld: "world"),
            budget: RoomBudgetSnapshot(window: 1000, trigger: 0.8, initialInput: 0, reservedOutput: 0, usable: 800, handoffAt: 600),
            compliance: AllowAll(),
            environment: [:],
            homeDirectory: "/tmp"
        )

        let text = RoomBriefing.text(spec: spec)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "작업: 스펙 기반 작업")
        #expect(lines[1] == "완료 조건: echo ok")
        #expect(lines[2] == "쓰기 가능: output/")
        #expect(lines[3] == "도구: cat, ls")
        #expect(lines[4] == "종료하려면 exit 를 입력하세요")
    }

    @Test("RoomSummary 로부터 4줄 안내문을 올바르게 생성한다")
    func testBriefingFromNode() {
        let node = RoomSummary(
            id: "room-node-1",
            kind: .standingRoom,
            title: "노드 기반 작업",
            status: .occupied
        )

        let text = RoomBriefing.text(node: node)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "작업: 노드 기반 작업")
        #expect(lines[1] == "완료 조건: 진행 중")
        #expect(lines[2] == "쓰기 가능: room-node-1")
        #expect(lines[3] == "도구: toolbelt")
        #expect(lines[4] == "종료하려면 exit 를 입력하세요")
    }
}
