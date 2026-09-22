import Foundation
import CommandKit
import InteropKit
import RoomKit
import AgentRoomTerminalCore

/// srt (sandbox-runtime) 경로로 방 세션을 기동하는 유틸리티.
enum SRTLaunch {
    /// srt 바이너리 경로. PATH 에서 탐색하고 없으면 nil.
    static let srtPath: String? = {
        let candidates = [
            "\(HostPlatform.homebrewBin)/srt",
            "/usr/local/bin/srt",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // PATH 에서 which 로 찾기
        let result = CommandKitSync.run("/usr/bin/which", ["srt"], timeout: 2)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }()

    /// srt 가 사용 가능한지 반환한다.
    static var isAvailable: Bool { srtPath != nil }

    /// srt 설정 JSON 을 방 폴더에 파일로 쓰고 경로를 반환한다.
    static func writeSettings(
        _ json: String,
        roomDir: String
    ) throws -> String {
        let url = URL(fileURLWithPath: roomDir)
            .appendingPathComponent("srt-settings.json", isDirectory: false)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// srt 로 감싼 셸 기동 명령을 생성한다. srt 가 없으면 nil.
    static func command(
        shell: String,
        settingsPath: String
    ) -> (executable: String, arguments: [String])? {
        guard let srt = srtPath else { return nil }
        let parsed = ShellLaunch.parse(shell)
        var args = ["--settings", settingsPath]
        args.append(parsed.executable)
        args.append(contentsOf: parsed.arguments)
        return (srt, args)
    }

    /// ExecRunner 용: srt 로 감싼 env 명령 배열을 반환한다.
    static func buildExecCommand(
        argv: [String],
        roomDir: String,
        env: [String: String],
        settingsPath: String
    ) -> [String] {
        guard let srt = srtPath else { return [] }
        var command = EnvFile.pairs(env)
        command.append(srt)
        command.append("--settings")
        command.append(settingsPath)
        command.append(AppPaths.zsh)
        command.append(["-", "c"].joined())
        command.append("cd \"$1\" && shift && exec \"$@\"")
        command.append("room-exec")
        command.append(roomDir)
        command.append(contentsOf: argv)
        return command
    }
}
