import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("BriefingFieldsResolver — 브리핑 헤더 필드 순수 계산")
struct BriefingFieldsResolverTests {
    private func makeInput(
        task: String = "작업",
        slug: String = "slug",
        verdict: String = "true",
        allowWrite: [String] = [],
        toolbelt: [String] = [],
        preset: RoomWallPreset = .toolbelt
    ) -> BriefingInput {
        BriefingInput(
            task: task,
            slug: slug,
            verdict: verdict,
            allowWrite: allowWrite,
            toolbelt: toolbelt,
            preset: preset,
            noneText: "없음",
            hostPathText: "호스트 전체 PATH"
        )
    }

    @Test("task·verdict·allowWrite·toolbelt 을 그대로 돌려준다")
    func resolvesFieldsFromDocument() {
        let input = makeInput(
            task: "카탈로그 배포",
            slug: "catalog-deploy",
            verdict: "swift test --filter Smoke",
            allowWrite: ["Sources", "Tests"],
            toolbelt: ["git", "swift"]
        )
        let fields = BriefingFieldsResolver.resolve(input: input, defaultToolsText: "기본 도구")
        #expect(fields.task == "카탈로그 배포")
        #expect(fields.verdict == "swift test --filter Smoke")
        #expect(fields.writePaths == "Sources, Tests")
        #expect(fields.tools == "git, swift")
    }

    @Test("task 이 비면 slug 를 대체한다")
    func fallsBackToSlugWhenTaskEmpty() {
        let input = makeInput(task: "", slug: "catalog-deploy")
        let fields = BriefingFieldsResolver.resolve(input: input, defaultToolsText: "기본 도구")
        #expect(fields.task == "catalog-deploy")
    }

    @Test("allowWrite 가 비면 noneText 를 표시한다")
    func showsNoneTextForEmptyWritePaths() {
        let input = makeInput(toolbelt: ["git"])
        let fields = BriefingFieldsResolver.resolve(input: input, defaultToolsText: "기본 도구")
        #expect(fields.writePaths == "없음")
    }

    @Test("toolbelt 이 비고 preset 이 open 이면 hostPathText 를 표시한다")
    func showsHostPathForOpenPreset() {
        let input = makeInput(allowWrite: ["~/work"], preset: .open)
        let fields = BriefingFieldsResolver.resolve(input: input, defaultToolsText: "기본 도구")
        #expect(fields.tools == "호스트 전체 PATH")
    }

    @Test("toolbelt 이 비고 preset 이 open 이 아니면 defaultToolsText 를 표시한다")
    func showsDefaultToolsForNonOpenPreset() {
        let input = makeInput(preset: .readOnly)
        let fields = BriefingFieldsResolver.resolve(input: input, defaultToolsText: "기본 도구")
        #expect(fields.tools == "기본 도구")
    }
}
