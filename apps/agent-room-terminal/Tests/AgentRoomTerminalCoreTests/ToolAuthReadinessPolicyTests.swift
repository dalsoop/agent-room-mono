import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("ToolAuthReadinessPolicy — 도구별 인증 준비 상태 정책")
struct ToolAuthReadinessPolicyTests {
    @Test("도구별 인증 검사 필요 여부 판정 (Claude만 true, agy/codex/grok은 false)")
    func toolAuthRequirementCheck() {
        #expect(ToolAuthReadinessPolicy.requiresAuthCheck(for: .claude))
        #expect(!ToolAuthReadinessPolicy.requiresAuthCheck(for: .agy))
        #expect(!ToolAuthReadinessPolicy.requiresAuthCheck(for: .codex))
        #expect(!ToolAuthReadinessPolicy.requiresAuthCheck(for: .grok))
    }

    @Test("다양한 agy 핸들(agent:antigravity, agent:agy, agy, antigravity) 입주 시 Claude 경고 억제(.notApplicable)")
    func agyOccupantSuppressesWarning() throws {
        let handles = [
            "agent:antigravity@macbook",
            "agent:agy@macbook",
            "agent:antigravity",
            "agy",
            "antigravity",
        ]
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-auth-agy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        for handle in handles {
            let occupants = [RoomOccupant(handle: handle, isSuccessor: false)]
            let tool = ToolAuthReadinessPolicy.resolveOccupantTool(roomURL: temp, occupants: occupants)
            #expect(tool == .agy)

            let readiness = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: occupants)
            #expect(readiness == .notApplicable)
            #expect(!readiness.shouldDisplayWarning)
        }
    }

    @Test("Claude 입주 시 자격 증명 시딩 여부에 따라 ready / unready 판정")
    func claudeOccupantEvaluatesCredentials() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-auth-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let occupants = [RoomOccupant(handle: "agent:claude@macbook", isSuccessor: false)]

        // 자격 증명 파일이 없는 경우 -> unready (경고 표시 대상)
        let unreadyResult = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: occupants)
        #expect(unreadyResult == .unready(tool: .claude, reason: "credentials_not_seeded"))
        #expect(unreadyResult.shouldDisplayWarning)

        // Claude config 디렉터리에 .credentials.json 생성 -> ready
        let configDir = AgentCredentialInjector.configDirName(tool: .claude, roomURL: temp)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try "{\"token\": \"test\"}".write(
            to: configDir.appendingPathComponent(".credentials.json"),
            atomically: true,
            encoding: .utf8
        )

        let readyResult = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: occupants)
        #expect(readyResult == .ready(tool: .claude))
        #expect(!readyResult.shouldDisplayWarning)
    }

    @Test("codex 및 grok 입주 시에는 인증 검사가 불필요하여 .notApplicable")
    func codexAndGrokDoNotRequireAuth() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-auth-others-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let codexOccupants = [RoomOccupant(handle: "agent:codex@host", isSuccessor: false)]
        let codexResult = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: codexOccupants)
        #expect(codexResult == .notApplicable)

        let grokOccupants = [RoomOccupant(handle: "agent:grok@host", isSuccessor: false)]
        let grokResult = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: grokOccupants)
        #expect(grokResult == .notApplicable)
    }

    @Test("입주자가 없고 spec도 없는 경우 임의의 경고를 띄우지 않고 .notApplicable")
    func unknownOccupantYieldsNotApplicable() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-auth-unknown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let result = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: [])
        #expect(result == .notApplicable)
        #expect(!result.shouldDisplayWarning)
    }

    @Test("spec.json에 지정된 도구가 agy인 경우 인증 경고 억제")
    func specWithAgySuppressesWarning() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-auth-spec-agy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let spec = RoomSpec(
            tenant: "tenant:test",
            task: "test",
            verdict: "true",
            launch: RoomLaunch(tool: .agy)
        )
        let data = try JSONEncoder().encode(spec)
        try data.write(to: temp.appendingPathComponent("spec.json"))

        let tool = ToolAuthReadinessPolicy.resolveOccupantTool(roomURL: temp, occupants: [])
        #expect(tool == .agy)

        let readiness = ToolAuthReadinessPolicy.evaluate(roomURL: temp, occupants: [])
        #expect(readiness == .notApplicable)
    }
}
