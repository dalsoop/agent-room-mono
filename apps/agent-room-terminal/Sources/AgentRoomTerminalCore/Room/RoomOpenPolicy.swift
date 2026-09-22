import Foundation
import RoomKit
import StateRootKit

/// 방을 열 때 CLI 와 GUI 가 같은 답을 내야 하는 판정 — seatbelt 프로필·후임 핸들.
/// 두 표면이 각자 계산하면 어긋난다(2차 검토 실측: GUI 가 프로필을 비우고 핸들을 리터럴로 둠).
public enum RoomOpenPolicy {
    /// 모든 프리셋이 seatbelt 를 켠다(business-rules 벽 프리셋 표). 쓰기 허용은 방 폴더·tmp·설계도 writePaths.
    /// open 프리셋은 셸(`zsh`)과 PATH 만 열고, 파일 쓰기 제한은 그대로 두며 네트워크는 허용한다.
    public static func seatbeltProfile(
        preset: RoomWallPreset,
        roomPath: String,
        writePaths: [String],
        network: NetworkWall,
        agentTools: [String] = [],
        homeDirectory: String = StateRootKit.resolveHost(environment: [:]),
        proxyPort: UInt16? = nil,
        workdir: String? = nil
    ) -> String? {
        var walls = RoomWalls.preset(preset)
        walls.filesystem.allowWrite = writePaths
        walls.network = network
        let spec = RoomSpec(
            tenant: "anonymous",
            task: "session",
            verdict: "allow",
            workdir: workdir,
            walls: walls
        )
        return SeatbeltCompiler.compile(
            spec: spec,
            roomDir: roomPath,
            home: homeDirectory,
            proxyPort: proxyPort,
            agentTools: agentTools
        ).profile
    }

    /// open 프리셋 + `.open` 벽은 전부 연다. `.allow` 는 프록시 포트만.
    static func allowAllOutbound(preset: RoomWallPreset, network: NetworkWall) -> Bool {
        switch network {
        case .open:
            return true
        case .allow:
            return false
        case .closed:
            return preset == .open
        }
    }

    static func proxyPortForProfile(network: NetworkWall, proxyPort: UInt16?) -> UInt16? {
        if case .allow = network { return proxyPort }
        return nil
    }

    /// 에이전트 CLI 가 자기 세션·자격증명을 쓰는 홈 밑 폴더. 그 도구가 방에 링크될 때만 연다.
    /// 홈 전체 쓰기 차단은 유지되고 이 폴더들만 예외다(실측 2026-09-03: HOME 쓰기 불가 → claude 세션 기록 실패).
    public static func agentStatePaths(agentTools: [String], homeDirectory: String) -> [String] {
        PathPlanner.agentStatePaths(agentTools: agentTools, homeDirectory: homeDirectory)
    }

    /// Antigravity CLI(agy) 의 홈 밑 상태 폴더 이름. 세션 DB·bin/agentapi 가 여기 쓰인다.
    public static let agyStateDirectory = PathPlanner.agyStateDirectory

    /// SwiftPM 이 홈 밑에 쓰는 캐시·보안 폴더. open 프리셋(코드 작업 방)에서만 연다.
    public static let swiftPMHomeDirectories = PathPlanner.swiftPMHomeDirectories

    /// open 프리셋에서 컴파일·커밋이 되게 하는 쓰기 예외 — SwiftPM 홈 캐시와 workdir 의 git 저장소.
    /// toolbelt·readOnly 는 빈 배열(실측 2026-09-05: 캐시 쓰기 거부로 `swift build` 불가, bare 저장소 거부로 커밋 불가).
    public static func buildToolchainStatePaths(
        preset: RoomWallPreset,
        workdir: String?,
        homeDirectory: String
    ) -> [String] {
        PathPlanner.buildToolchainStatePaths(preset: preset, workdir: workdir, homeDirectory: homeDirectory)
    }

    /// workdir 의 git 저장소 쓰기 경로. `.git` 이 디렉터리면 그 자체, worktree(`.git` 파일의
    /// `gitdir: <bare>/worktrees/<name>`)면 공용 저장소(`<bare>`) — objects·refs·worktree 메타가 모두 그 밑이다.
    public static func gitRepositoryWritePath(
        workdir: String?,
        fileManager: FileManager = .default
    ) -> String? {
        PathPlanner.gitRepositoryWritePath(workdir: workdir, fileManager: fileManager)
    }

    /// `.git` 파일 본문(`gitdir: …`)에서 공용 저장소 경로를 푼다. 순수 함수 — 테스트용.
    public static func gitCommonDirectory(fromGitFile text: String, workdir: String) -> String? {
        PathPlanner.gitCommonDirectory(fromGitFile: text, workdir: workdir)
    }

    /// 설계도 writePaths 의 `/**` 꼬리를 떼고, 상대경로는 작업 디렉터리(worktree) 기준으로 편다.
    /// workdir 이 없으면 방 폴더 기준이다(실측 2026-09-05: 방 폴더 기준으로 풀면 worktree 쓰기가 전부 막힌다).
    public static func resolvedWritePaths(
        roomPath: String,
        workdir: String? = nil,
        writePaths: [String]
    ) -> [String] {
        PathPlanner.resolvedWritePaths(roomPath: roomPath, workdir: workdir, writePaths: writePaths)
    }

    /// 후임 핸들은 전임 세션에서 파생한다 — 리터럴 "successor" 는 방 둘에서 충돌한다.
    public static func successorHandle(sessionID: String) -> String {
        let head = sessionID.isEmpty ? "gui" : String(sessionID.prefix(8))
        return "\(head)-successor"
    }

    /// 원장이 simulating 이고 요청자가 후임이면 전임 세션을 재사용하지 않는다.
    /// `--successor` 이거나, 후임 occupant 가 전임과 다르거나 successorOccupant 와 같다.
    public static func shouldOpenSuccessor(
        flag: Bool,
        handoverState: String,
        occupant: String,
        successorOccupant: String,
        requestedOccupant: String
    ) -> Bool {
        if flag { return true }
        guard handoverState == "simulating" else { return false }
        if !successorOccupant.isEmpty,
           requestedOccupant == successorOccupant,
           successorOccupant != occupant {
            return true
        }
        if !occupant.isEmpty, requestedOccupant != occupant {
            return true
        }
        return false
    }

    /// 원장이 이미 simulating 이고 후임 핸들이 빈병(전임 세션에서 파생)과 같으면
    /// occupy --successor / handover 를 다시 치지 않는다. 원장은 simulating → simulating 을 거부한다.
    public static func shouldJoinExistingHandover(
        handoverState: String,
        successorSession: String,
        bottleSuccessorHandle: String
    ) -> Bool {
        guard handoverState == "simulating" else { return false }
        guard !successorSession.isEmpty, !bottleSuccessorHandle.isEmpty else { return false }
        return successorSession == bottleSuccessorHandle
    }

    public static func successorHandleFromLatestBottle(in roomURL: URL) -> String? {
        do {
            guard let bottle = try HandoffIO.lastBottle(in: roomURL), !bottle.sessionID.isEmpty else {
                return nil
            }
            return successorHandle(sessionID: bottle.sessionID)
        } catch {
            return nil
        }
    }
}
