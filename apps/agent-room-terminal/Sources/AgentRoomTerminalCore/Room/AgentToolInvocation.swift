import Foundation

/// 방 밖에서 매번 플래그를 새로 맞추지 않도록, 도구별 무인(non-interactive) 단발 실행 규격을 표로 둔다.
/// tty 를 안 주는 실행(exec, 스모크 테스트, 자동화)은 전부 이 규격을 따라야 "Device not configured" 류
/// 도구별 UI 시도 실패를 피한다(실측 2026-09-04: codex 는 --skip-git-repo-check, grok 은 -p 필요).
public enum AgentToolInvocation {
    /// tool 뒤에 붙일 인자. `%PROMPT%` 를 실제 프롬프트 문자열로 치환해서 쓴다.
    static let templates: [AgentRoomTool: [String]] = [
        .claude: ["-p", "%PROMPT%", "--max-turns", "1"],
        .codex: ["exec", "--skip-git-repo-check", "%PROMPT%"],
        .grok: ["--always-approve", "-p", "%PROMPT%"],
        // agy(Antigravity) 는 무인 단발 실행 규격이 실측되지 않았다 — 표에 없으면 호출자가 직접 판단한다.
    ]

    public static func arguments(tool: AgentRoomTool, prompt: String) -> [String]? {
        templates[tool]?.map { $0 == "%PROMPT%" ? prompt : $0 }
    }
}
