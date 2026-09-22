import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomBinPlanner.agentHelpers — claude 는 security 를 데려간다")
struct AgentHelperTests {
    @Test func claudeBringsSecurity() {
        #expect(RoomBinPlanner.agentHelpers["claude"] == ["security"])
        #expect(RoomBinPlanner.agentHelpers["grok"] == nil)
    }
}

@Suite("RoomOpenPolicy — 에이전트 상태 폴더만 seatbelt 쓰기 예외")
struct RoomOpenPolicyTests {
    @Test("링크된 도구의 홈 폴더만 허용 목록에 든다")
    func agentStatePaths() {
        let paths = RoomOpenPolicy.agentStatePaths(agentTools: ["claude", "grok"], homeDirectory: "/Users/x")
        #expect(paths == ["/Users/x/.claude", "/Users/x/.claude.json", "/Users/x/.grok"])
        #expect(RoomOpenPolicy.agentStatePaths(agentTools: [], homeDirectory: "/Users/x").isEmpty)
    }

    @Test("agy 는 ~/.gemini 상태 폴더를 연다")
    func agyStatePath() {
        let paths = RoomOpenPolicy.agentStatePaths(agentTools: ["agy"], homeDirectory: "/Users/x")
        #expect(paths == ["/Users/x/.gemini"])
    }

    @Test("open 프리셋만 SwiftPM 캐시와 git 저장소 쓰기를 연다")
    func buildToolchainPathsOnlyForOpen() {
        #expect(RoomOpenPolicy.buildToolchainStatePaths(
            preset: .toolbelt, workdir: "/wt", homeDirectory: "/Users/x").isEmpty)
        let open = RoomOpenPolicy.buildToolchainStatePaths(
            preset: .open, workdir: nil, homeDirectory: "/Users/x")
        #expect(open == [
            "/Users/x/Library/Caches/org.swift.swiftpm",
            "/Users/x/Library/org.swift.swiftpm",
            "/Users/x/.swiftpm",
        ])
    }

    @Test("worktree .git 파일은 공용 bare 저장소로, 상대 gitdir 도 workdir 기준으로 푼다")
    func gitCommonDirectoryFromGitFile() {
        let absolute = RoomOpenPolicy.gitCommonDirectory(
            fromGitFile: "gitdir: /repo/.bare/worktrees/w1\n", workdir: "/repo/.worktrees/w1")
        #expect(absolute == "/repo/.bare")
        let relative = RoomOpenPolicy.gitCommonDirectory(
            fromGitFile: "gitdir: ../../.bare/worktrees/w1", workdir: "/repo/.worktrees/w1")
        #expect(relative == "/repo/.bare")
        let plain = RoomOpenPolicy.gitCommonDirectory(
            fromGitFile: "gitdir: /elsewhere/.git/modules/sub", workdir: "/repo")
        #expect(plain == "/elsewhere/.git/modules/sub")
        #expect(RoomOpenPolicy.gitCommonDirectory(fromGitFile: "garbage", workdir: "/repo") == nil)
    }

    @Test("상대 writePaths 는 workdir 기준, 없으면 방 폴더 기준")
    func relativeWritePathsResolveAgainstWorkdir() {
        let withWorkdir = RoomOpenPolicy.resolvedWritePaths(
            roomPath: "/rooms/r1", workdir: "/wt/app", writePaths: ["apps/x/**", "/abs/y/**"])
        #expect(withWorkdir == ["/wt/app/apps/x", "/abs/y"])
        let withoutWorkdir = RoomOpenPolicy.resolvedWritePaths(
            roomPath: "/rooms/r1", writePaths: ["apps/x/**"])
        #expect(withoutWorkdir == ["/rooms/r1/apps/x"])
        let emptyWorkdir = RoomOpenPolicy.resolvedWritePaths(
            roomPath: "/rooms/r1", workdir: "", writePaths: ["apps/x"])
        #expect(emptyWorkdir == ["/rooms/r1/apps/x"])
    }

    @Test("simulating 이고 --successor 이면 후임 세션을 연다")
    func successorFlagOpensNewSession() {
        #expect(RoomOpenPolicy.shouldOpenSuccessor(
            flag: true,
            handoverState: "simulating",
            occupant: "agent:claude@host",
            successorOccupant: "agent:claude@host",
            requestedOccupant: "agent:claude@host"
        ))
        #expect(!RoomOpenPolicy.shouldOpenSuccessor(
            flag: false,
            handoverState: "simulating",
            occupant: "agent:claude@host",
            successorOccupant: "agent:claude@host",
            requestedOccupant: "agent:claude@host"
        ))
        #expect(RoomOpenPolicy.shouldOpenSuccessor(
            flag: false,
            handoverState: "simulating",
            occupant: "agent:claude@host",
            successorOccupant: "",
            requestedOccupant: "agent:grok@host"
        ))
        #expect(!RoomOpenPolicy.shouldOpenSuccessor(
            flag: false,
            handoverState: "none",
            occupant: "agent:claude@host",
            successorOccupant: "",
            requestedOccupant: "agent:grok@host"
        ))
    }

    @Test("simulating 이고 후임 핸들이 빈병과 같으면 join — 아니면 handover")
    func joinExistingHandover() {
        let handle = RoomOpenPolicy.successorHandle(sessionID: "aaaaaaaa-bbbb")
        #expect(RoomOpenPolicy.shouldJoinExistingHandover(
            handoverState: "simulating",
            successorSession: handle,
            bottleSuccessorHandle: handle
        ))
        #expect(!RoomOpenPolicy.shouldJoinExistingHandover(
            handoverState: "none",
            successorSession: handle,
            bottleSuccessorHandle: handle
        ))
        #expect(!RoomOpenPolicy.shouldJoinExistingHandover(
            handoverState: "simulating",
            successorSession: "other-handle",
            bottleSuccessorHandle: handle
        ))
    }

    @Test("프로필에 홈 전체 쓰기 차단과 .claude 예외가 같이 실린다")
    func profileCarriesException() throws {
        let scheme = try #require(RoomOpenPolicy.seatbeltProfile(
            preset: .toolbelt, roomPath: "/tmp/room", writePaths: [], network: true,
            agentTools: ["claude"], homeDirectory: "/Users/x"
        ))
        #expect(scheme.contains("(allow file-write* (subpath \"/Users/x/.claude\"))"))
        #expect(scheme.contains("(deny file-write*"))
    }
}
