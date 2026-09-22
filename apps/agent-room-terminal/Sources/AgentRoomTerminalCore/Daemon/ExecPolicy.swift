import Foundation
import RoomKit

/// 데몬 `exec` 가 방의 벽을 우회하지 못하게 하는 순수 판정.
/// 세션이 제한 셸(`zsh -r`)이면 절대경로·상대경로 실행(`/usr/bin/curl`, `./x`)과
/// 셸 우회(`sh -c`·`env PATH=`)를 막는다 — 터미널의 `zsh -r` 가 막는 것과 같은 선.
/// 파괴 명령은 실행하지 않고 `quarantine`, 방 밖 절대경로 인자는 방 `work/` 로 `redirect`.
public enum ExecDecision: Equatable, Sendable {
    case allow
    case deny(reason: String)
    case redirect(argv: [String], reason: String)
    case quarantine(reason: String)
}

public enum ExecPolicy {
    public static var shellBypass: Set<String> { ExecRule.shellBypass }

    /// 거부 사유. nil 이면 통과. 절대경로·셸 우회만 본다(구 API).
    public static func rejection(argv: [String], restricted: Bool) -> String? {
        let walls = RoomWalls(
            executables: .hostPath,
            shell: restricted ? .restricted : .normal
        )
        if case .deny(let reason) = ExecRule.decide(argv: argv, walls: walls) {
            return reason
        }
        return nil
    }

    /// `zsh -r` 처럼 `-r` 플래그가 있으면 제한 셸이다.
    public static func isRestricted(shell: String) -> Bool {
        shell.split(separator: " ").contains("-r")
    }

    public static func decision(
        argv: [String],
        restricted: Bool,
        roomDir: String,
        writePaths: [String]
    ) -> ExecDecision {
        let walls = RoomWalls(
            filesystem: FilesystemWall(allowWrite: writePaths),
            executables: .hostPath,
            shell: restricted ? .restricted : .normal
        )
        let ruleDecision = ExecRule.decide(argv: argv, walls: walls)
        switch ruleDecision {
        case .deny(let reason):
            return .deny(reason: reason)
        case .quarantine(let reason):
            return .quarantine(reason: reason)
        case .allow:
            if let redirected = redirectArgv(argv: argv, roomDir: roomDir, writePaths: writePaths) {
                return .redirect(argv: redirected.argv, reason: redirected.reason)
            }
            return .allow
        }
    }

    /// 방 `ROOM.json` 의 `walls.writePaths`. 없거나 깨지면 빈 배열.
    public static func writePaths(roomDir: String) -> [String] {
        let url = URL(fileURLWithPath: roomDir).appendingPathComponent("ROOM.json")
        do {
            let data = try Data(contentsOf: url)
            let root = try JSONSerialization.jsonObject(with: data)
            guard let object = root as? [String: Any],
                  let walls = object["walls"] as? [String: Any],
                  let paths = walls["writePaths"] as? [String]
            else { return [] }
            return paths
        } catch {
            return []
        }
    }

    public static func quarantineReason(argv: [String]) -> String? {
        ExecRule.quarantineReason(argv: argv)
    }

    private static func redirectArgv(
        argv: [String],
        roomDir: String,
        writePaths: [String]
    ) -> (argv: [String], reason: String)? {
        guard argv.count > 1 else { return nil }
        let room = (roomDir as NSString).standardizingPath
        var next = argv
        var changed = false
        for index in 1..<argv.count {
            let token = argv[index]
            guard token.hasPrefix("/") else { continue }
            let absolute = (token as NSString).standardizingPath
            if isInsideRoom(absolute, roomDir: room) { continue }
            if isCovered(absolute, writePaths: writePaths, roomDir: room) { continue }
            let name = URL(fileURLWithPath: absolute).lastPathComponent
            guard !name.isEmpty, name != "/" else { continue }
            let candidate = ((room as NSString)
                .appendingPathComponent("work") as NSString)
                .appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            next[index] = candidate
            changed = true
        }
        guard changed else { return nil }
        return (next, "redirected outside path into room work/")
    }

    private static func isInsideRoom(_ path: String, roomDir: String) -> Bool {
        path == roomDir || path.hasPrefix(roomDir + "/")
    }

    private static func isCovered(_ path: String, writePaths: [String], roomDir: String) -> Bool {
        for pattern in writePaths {
            let expanded: String
            if pattern.hasPrefix("/") {
                expanded = pattern
            } else {
                expanded = (roomDir as NSString).appendingPathComponent(pattern)
            }
            if expanded.hasSuffix("/**") {
                let base = String(expanded.dropLast(3))
                if path == base || path.hasPrefix(base + "/") { return true }
            } else if path == (expanded as NSString).standardizingPath {
                return true
            }
        }
        return false
    }
}
