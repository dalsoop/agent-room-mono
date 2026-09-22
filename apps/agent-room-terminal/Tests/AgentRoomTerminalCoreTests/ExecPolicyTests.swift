import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("ExecPolicy — exec 도 zsh -r 과 같은 선에서 막는다")
struct ExecPolicyTests {
    @Test("제한 셸에서 절대경로·상대경로·셸 우회는 거부")
    func restrictedRejects() {
        #expect(ExecPolicy.rejection(argv: ["/usr/bin/curl", "x"], restricted: true) != nil)
        #expect(ExecPolicy.rejection(argv: ["./run"], restricted: true) != nil)
        #expect(ExecPolicy.rejection(argv: ["sh", "-c", "ls"], restricted: true) != nil)
        #expect(ExecPolicy.rejection(argv: ["env", "PATH=/x", "ls"], restricted: true) != nil)
    }

    @Test("제한 셸에서도 toolbelt 이름 호출은 통과")
    func restrictedAllowsBareNames() {
        #expect(ExecPolicy.rejection(argv: ["gujo-support-desk", "capabilities"], restricted: true) == nil)
        #expect(ExecPolicy.rejection(argv: ["ls", "bin"], restricted: true) == nil)
    }

    @Test("open 프리셋(비제한 셸)은 전부 통과")
    func openAllowsEverything() {
        #expect(ExecPolicy.rejection(argv: ["/usr/bin/curl"], restricted: false) == nil)
        #expect(ExecPolicy.isRestricted(shell: "zsh -r"))
        #expect(!ExecPolicy.isRestricted(shell: "zsh"))
    }

    @Test("제한 셸 절대경로 실행은 deny")
    func decisionDeniesAbsolutePathWhenRestricted() {
        let d = ExecPolicy.decision(
            argv: ["/usr/bin/curl", "https://x"],
            restricted: true,
            roomDir: "/tmp/room",
            writePaths: []
        )
        guard case .deny(let reason) = d else {
            Issue.record("expected deny, got \(d)")
            return
        }
        #expect(reason.contains("path execution"))
    }

    @Test("제한 셸 우회는 deny")
    func decisionDeniesShellBypass() {
        let d = ExecPolicy.decision(
            argv: ["bash", "-c", "ls"],
            restricted: true,
            roomDir: "/tmp/room",
            writePaths: []
        )
        guard case .deny = d else {
            Issue.record("expected deny, got \(d)")
            return
        }
    }

    @Test("제한 셸 맨이름 호출은 allow")
    func decisionAllowsBareName() {
        let d = ExecPolicy.decision(
            argv: ["ls", "bin"],
            restricted: true,
            roomDir: "/tmp/room",
            writePaths: []
        )
        #expect(d == .allow)
    }

    @Test("비제한 셸 절대경로 실행은 allow")
    func decisionAllowsAbsoluteWhenOpen() {
        let d = ExecPolicy.decision(
            argv: ["/usr/bin/curl"],
            restricted: false,
            roomDir: "/tmp/room",
            writePaths: []
        )
        #expect(d == .allow)
    }

    @Test("rm -rf 는 quarantine")
    func decisionQuarantinesRmRf() {
        let d = ExecPolicy.decision(
            argv: ["rm", "-rf", "/"],
            restricted: true,
            roomDir: "/tmp/room",
            writePaths: []
        )
        guard case .quarantine(let reason) = d else {
            Issue.record("expected quarantine, got \(d)")
            return
        }
        #expect(reason.contains("rm -rf"))
    }

    @Test("git push --force 는 quarantine")
    func decisionQuarantinesGitForcePush() {
        let d = ExecPolicy.decision(
            argv: ["git", "push", "--force", "origin", "main"],
            restricted: true,
            roomDir: "/tmp/room",
            writePaths: []
        )
        guard case .quarantine(let reason) = d else {
            Issue.record("expected quarantine, got \(d)")
            return
        }
        #expect(reason.contains("git push --force"))
    }

    @Test("kubectl delete 는 quarantine")
    func decisionQuarantinesKubectlDelete() {
        let d = ExecPolicy.decision(
            argv: ["kubectl", "delete", "pod", "x"],
            restricted: false,
            roomDir: "/tmp/room",
            writePaths: []
        )
        guard case .quarantine(let reason) = d else {
            Issue.record("expected quarantine, got \(d)")
            return
        }
        #expect(reason.contains("kubectl delete"))
    }

    @Test("방 밖 절대경로 인자는 work/ 에 같은 이름이 있으면 redirect")
    func decisionRedirectsOutsidePathToWork() throws {
        let room = FileManager.default.temporaryDirectory
            .appendingPathComponent("exec-redirect-\(UUID().uuidString)", isDirectory: true)
        let work = room.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: room) }
        let inside = work.appendingPathComponent("notes.txt")
        try Data("in-room".utf8).write(to: inside)
        let d = ExecPolicy.decision(
            argv: ["cat", "/tmp/notes.txt"],
            restricted: true,
            roomDir: room.path,
            writePaths: []
        )
        guard case .redirect(let argv, let reason) = d else {
            Issue.record("expected redirect, got \(d)")
            return
        }
        #expect(argv == ["cat", inside.path])
        #expect(reason.contains("work"))
    }

    @Test("work/ 에 같은 이름이 없으면 redirect 하지 않는다")
    func decisionDoesNotRedirectMissingWorkFile() {
        let d = ExecPolicy.decision(
            argv: ["cat", "/tmp/missing-unique-name-xyz.txt"],
            restricted: true,
            roomDir: "/tmp/room-does-not-exist-\(UUID().uuidString)",
            writePaths: []
        )
        #expect(d == .allow)
    }

    @Test("open 프리셋에서도 파괴적 명령(rm -rf, git push --force, kubectl delete)은 quarantine")
    func openPresetStillQuarantinesDestructiveCommands() {
        let room = "/tmp/room"
        let dGit = ExecPolicy.decision(
            argv: ["/usr/bin/git", "status"],
            restricted: false,
            roomDir: room,
            writePaths: []
        )
        #expect(dGit == .allow)

        let dRm = ExecPolicy.decision(
            argv: ["rm", "-rf", "/tmp/anything"],
            restricted: false,
            roomDir: room,
            writePaths: []
        )
        guard case .quarantine(let reasonRm) = dRm else {
            Issue.record("expected quarantine for rm -rf, got \(dRm)")
            return
        }
        #expect(reasonRm.contains("rm -rf"))

        let dPush = ExecPolicy.decision(
            argv: ["git", "push", "--force", "origin", "main"],
            restricted: false,
            roomDir: room,
            writePaths: []
        )
        guard case .quarantine(let reasonPush) = dPush else {
            Issue.record("expected quarantine for git push --force, got \(dPush)")
            return
        }
        #expect(reasonPush.contains("git push --force"))

        let dKube = ExecPolicy.decision(
            argv: ["kubectl", "delete", "namespace", "default"],
            restricted: false,
            roomDir: room,
            writePaths: []
        )
        guard case .quarantine(let reasonKube) = dKube else {
            Issue.record("expected quarantine for kubectl delete, got \(dKube)")
            return
        }
        #expect(reasonKube.contains("kubectl delete"))
    }
}

