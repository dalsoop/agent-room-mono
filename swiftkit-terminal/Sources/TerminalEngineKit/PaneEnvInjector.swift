import Foundation

/// 셸 명령에 샌드박스 env 를 심는 순수 함수.
public enum PaneEnvInjector {
    /// command 가 비면 로그인 셸을 export 후 exec, 있으면 export 후 exec argv.
    public static func wrap(command: [String], shell: String, sandbox: PaneSandbox) -> [String] {
        let exports = sandbox.exportPrefix
        guard !exports.isEmpty else {
            if command.isEmpty { return [shell, "-l"] }
            return [shell, "-l", "-c", "exec " + command.map(PaneSandbox.shellQuote).joined(separator: " ")]
        }
        if command.isEmpty {
            // 대화형 셸 — env 를 심은 뒤 같은 셸을 다시 exec.
            return [shell, "-l", "-c", "\(exports); exec \(PaneSandbox.shellQuote(shell)) -l"]
        }
        let body = "exec " + command.map(PaneSandbox.shellQuote).joined(separator: " ")
        return [shell, "-l", "-c", "\(exports); \(body)"]
    }

    /// 터미널 환경변수 형식(`KEY=VALUE` 배열)에 sandbox env 를 합친다(같은 키는 덮어씀).
    public static func merge(base: [String], sandbox: PaneSandbox) -> [String] {
        var map: [String: String] = [:]
        for entry in base {
            if let eq = entry.firstIndex(of: "=") {
                let k = String(entry[..<eq])
                let v = String(entry[entry.index(after: eq)...])
                map[k] = v
            }
        }
        for (k, v) in sandbox.environment { map[k] = v }
        return map.keys.sorted().map { "\($0)=\(map[$0]!)" }
    }
}
