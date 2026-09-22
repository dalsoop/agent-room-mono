import Darwin
import Foundation
import CommandKit

/// 테스트 또는 런타임 종료 시 남은 `agent-room-terminal-daemon` 프로세스를 추적하여
/// SIGTERM 후 SIGKILL 로 안전하게 회수하는 유틸리티.
public enum DaemonProcessReaper: Sendable {
    /// 지정된 root 디렉터리(예: `/tmp/art-*`)와 연결된 소켓 및 데몬 프로세스를 회수한다.
    public static func reapDaemons(root: URL) {
        let pattern = root.path
        reapMatching(pattern: pattern)
        // 직접 소켓 또는 .tenants/_daemon 하위 소켓 확인
        let directSock = root.appendingPathComponent("s.sock")
        let tenantSock = root.appendingPathComponent(".tenants/_daemon/agent-room-terminal.sock")
        for sock in [directSock, tenantSock] {
            if let pid = peerPID(socketURL: sock) {
                killPID(pid)
            }
        }
    }

    /// `/tmp/art-` 소켓 경로를 가진 모든 테스트 데몬 프로세스를 찾아 회수한다.
    public static func reapAllTestDaemons() {
        reapMatching(pattern: "agent-room-terminal-daemon.*--socket.*/tmp/art-")
        reapMatching(pattern: "agent-room-terminal-daemon --socket /tmp/art-")
    }

    /// pgrep 패턴으로 검색된 모든 데몬 프로세스를 종료한다.
    public static func reapMatching(pattern: String) {
        let result = CommandKitSync.run("/usr/bin/pgrep", ["-f", pattern], timeout: 5)
        guard result.exitCode == 0 else { return }
        let pids = result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        for pid in pids where pid > 1 && pid != getpid() {
            killPID(pid)
        }
    }

    /// 단일 PID 에 대해 SIGTERM 전송 후 종료를 대기하고, 미종료 시 SIGKILL 을 전송한다.
    public static func killPID(_ pid: pid_t) {
        guard kill(pid, 0) == 0 else { return }
        kill(pid, SIGTERM)
        // 최대 500ms 동안 SIGTERM 대기 (25ms 간격)
        for _ in 0..<20 {
            if kill(pid, 0) != 0 { return }
            var spec = timespec(tv_sec: 0, tv_nsec: 25_000_000)
            nanosleep(&spec, nil)
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
            for _ in 0..<10 {
                if kill(pid, 0) != 0 { return }
                var spec = timespec(tv_sec: 0, tv_nsec: 25_000_000)
                nanosleep(&spec, nil)
            }
        }
    }

    /// UNIX 도메인 소켓에 연결하여 `LOCAL_PEERPID` 로 데몬의 PID 를 가져온다.
    public static func peerPID(socketURL: URL) -> pid_t? {
        guard access(socketURL.path, F_OK) == 0 else { return nil }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        guard let address = try? UnixSocketIO.socketAddress(path: socketURL.path) else { return nil }
        var addrCopy = address
        let connected = withUnsafePointer(to: &addrCopy) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected else { return nil }
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        let optRes = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLen)
        guard optRes == 0, pid > 1 else { return nil }
        return pid
    }
}
