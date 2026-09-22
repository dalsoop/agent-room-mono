import CommandKit
import Foundation

/// seatbelt(sandbox-exec) 는 macOS Keychain IPC 를 막는다(실측 2026-09-04) — 그 방식으로
/// 인증하는 도구는 방 안에서 `/login` 이 항상 실패한다. 파일 읽기는 seatbelt 가 막지 않으므로,
/// keychain 값을 방 밖(이 프로세스, keychain 접근 가능)에서 꺼내 방 전용 config 디렉터리에
/// 파일로 복제해두면 그 도구가 그 파일로 인증한다. 새 토큰 발급도 사람 개입도 필요 없다.
///
/// codex·grok 은 이미 파일 기반 인증(`~/.codex/auth.json`, `~/.grok/auth.json`)이라 이 우회가
/// 필요 없다 — seatbelt 는 애초에 그 파일들의 읽기를 막지 않는다(agentStatePaths 의 쓰기 예외로
/// 세션 갱신만 커버하면 충분). 도구별로 다르면 여기 표만 늘리면 된다.
public enum AgentCredentialInjector {
    struct KeychainStrategy {
        let service: String
        let configDirEnvKey: String
        let fileName: String
    }

    static let strategies: [AgentRoomTool: KeychainStrategy] = [
        .claude: KeychainStrategy(
            service: "Claude Code-credentials",
            configDirEnvKey: "CLAUDE_CONFIG_DIR",
            fileName: ".credentials.json"
        ),
    ]

    /// 방 폴더 밑 도구 전용 config 디렉터리. 사용자의 진짜 `~/.claude` 등과 분리해
    /// 실제 로그인 세션에 영향을 주지 않는다.
    public static func configDirName(tool: AgentRoomTool, roomURL: URL) -> URL {
        roomURL.appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("\(tool.rawValue)-config", isDirectory: true)
    }

    /// 해당 도구가 keychain 전략을 쓸 때만 env 키 이름을 돌려준다(RoomEnvFile 이 값 계산에 쓴다).
    public static func configDirEnvKey(for tool: AgentRoomTool) -> String? {
        strategies[tool]?.configDirEnvKey
    }

    /// `open` 결과가 사용자에게 보여줄 시딩 상태. 조용히 실패하면 keychain 없는 호스트(CI 등)에서
    /// 원인 추적이 오래 걸린다(실측 2026-09-04) — 호출자가 이 값을 결과 JSON 에 그대로 노출한다.
    public enum SeedOutcome: String, Sendable {
        case notApplicable
        case seeded
        case failed
    }

    @discardableResult
    public static func seed(tool: AgentRoomTool, roomURL: URL) -> SeedOutcome {
        guard let strategy = strategies[tool] else { return .notApplicable }
        guard let payload = readKeychainPayload(service: strategy.service) else { return .failed }
        let wrote = writeCredentials(
            payload,
            to: configDirName(tool: tool, roomURL: roomURL),
            fileName: strategy.fileName
        )
        return wrote ? .seeded : .failed
    }

    /// seed 가 만든 도구별 config 디렉터리를 통째로 지운다. 없으면 true.
    /// 실패해도 예외를 던지지 않고 사유를 stderr 에 남긴 뒤 false.
    /// 자격증명 **파일만** 안전하게 덮어쓰고(wipe) 지운다(unlink). 같은 폴더의 `projects/`(전사)는
    /// 사용량·문서 관측의 증거라 남긴다(실측 2026-09-04: 폴더째 지우니 방 안 세션 전사가 close 와 함께 사라졌다).
    @discardableResult
    public static func unseed(tool: AgentRoomTool, roomURL: URL) -> Bool {
        guard let strategy = strategies[tool] else { return true }
        let dir = configDirName(tool: tool, roomURL: roomURL)
        let file = dir.appendingPathComponent(strategy.fileName)
        let fm = FileManager()
        guard fm.fileExists(atPath: file.path) else { return true }
        do {
            try wipeAndRemove(file: file)
            return true
        } catch {
            fputs(
                "credential unseed failed (\(tool.rawValue) \(dir.path)): \(error.localizedDescription)\n",
                stderr
            )
            return false
        }
    }

    /// 방 내의 모든 도구에 대해 자격증명 사본을 안전하게 삭제(wipe/unlink)한다.
    @discardableResult
    public static func unseedAll(roomURL: URL) -> Bool {
        var allSucceeded = true
        for tool in AgentRoomTool.allCases {
            if !unseed(tool: tool, roomURL: roomURL) {
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    /// 방 자격증명 사본 수명 종료 시 안전 삭제(wipe)
    @discardableResult
    public static func wipe(roomURL: URL) -> Bool {
        unseedAll(roomURL: roomURL)
    }

    private static func wipeAndRemove(file: URL) throws {
        let fm = FileManager()
        guard fm.fileExists(atPath: file.path) else { return }
        do {
            let attrs = try fm.attributesOfItem(atPath: file.path)
            if let size = attrs[.size] as? UInt64, size > 0 {
                let zeros = Data(repeating: 0, count: Int(size))
                do {
                    try zeros.write(to: file, options: .atomic)
                } catch {
                    fputs("credential wipe overwrite failed (\(file.path)): \(error.localizedDescription)\n", stderr)
                }
            }
        } catch {
            fputs("credential wipe read attrs failed (\(file.path)): \(error.localizedDescription)\n", stderr)
        }
        try fm.removeItem(at: file)
    }

    private static func readKeychainPayload(service: String) -> String? {
        let result = CommandKitSync.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", service, "-w"],
            timeout: 10
        )
        let payload = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !payload.isEmpty else { return nil }
        return payload
    }

    private static func writeCredentials(_ payload: String, to configDir: URL, fileName: String) -> Bool {
        let fm = FileManager()
        do {
            try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            let url = configDir.appendingPathComponent(fileName)
            try Data(payload.utf8).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
