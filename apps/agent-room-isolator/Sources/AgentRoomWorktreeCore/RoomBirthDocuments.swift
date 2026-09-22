import Foundation

/// 방 폴더에 심는 세 MD. 레포 루트 AGENTS.md 는 건드리지 않는다.
public enum RoomBirthDocuments {
    public static let names = ["ROOM.md", "DESIGN.md", "AGENTS.md"]

    public static func render(name: String, bind: RoomWorktreeBind, wallPreset: String, network: Bool) -> String {
        let networkLabel = network ? "open" : "closed"
        let values: [String: String] = [
            "ROOM_SLUG": bind.slug,
            "ROOM_ID": bind.roomID,
            "PLAN_ID": bind.planID,
            "TENANT_ID": bind.tenantID,
            "TASK": bind.task,
            "VERIFY": bind.verify,
            "WALL_PRESET": wallPreset,
            "WORKTREE_PATH": bind.worktreePath,
            "BRANCH": bind.branch,
            "REPO": bind.repoPath,
            "NETWORK": networkLabel,
        ]
        return substitute(template(for: name), values)
    }

    static func substitute(_ template: String, _ values: [String: String]) -> String {
        var out = template
        for (key, value) in values {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return out
    }

    static func template(for name: String) -> String {
        switch name {
        case "ROOM.md": return roomTemplate
        case "DESIGN.md": return designTemplate
        case "AGENTS.md": return agentsTemplate
        default: return ""
        }
    }

    static let roomTemplate = """
    # 방 {{ROOM_SLUG}}

    이 파일은 **이 방의 개념**이다. 레포 루트 `AGENTS.md` 가 아니다.

    | 항목 | 값 |
    |---|---|
    | roomID | `{{ROOM_ID}}` |
    | planID | `{{PLAN_ID}}` |
    | tenant | `{{TENANT_ID}}` |
    | task | {{TASK}} |
    | verdict | `{{VERIFY}}` |
    | wallPreset | `{{WALL_PRESET}}` |
    | worktree | `{{WORKTREE_PATH}}` |
    | branch | `{{BRANCH}}` |
    | repo | `{{REPO}}` |

    ## 벽

    - 쓰기: 워크트리와 이 방 폴더만.
    - 네트워크: {{NETWORK}} (기본 닫힘).
    - 셸: restricted. 호스트 설정(`.zshrc` 등) 쓰기 거부.

    ## 완료

    아래 명령이 exit 0 일 때만 이 방은 끝난다. 자기평가는 완료가 아니다.

    ```bash
    {{VERIFY}}
    ```

    ## 위임

    | 일 | CLI |
    |---|---|
    | 원장 | `agent-work-todo` |
    | git worktree | `agent-worktree-control-terminal` |
    | 방 터미널 | `agent-room-terminal` |
    | 결속·이 MD | `agent-room-worktree` |
    """

    static let designTemplate = """
    # 설계 — {{ROOM_SLUG}}

    이 방이 만들 것의 설계다. 모르는 자리는 TODO 로 비운다. 지어내지 않는다.

    ## 한 줄

    {{TASK}}

    ## 범위

    - 한다:
      <!-- TODO: 이 방이 만지는 파일·CLI·표면 -->
    - 안 한다:
      <!-- TODO: 위임할 앱 / 만지면 안 되는 경계 -->

    ## 계약

    - 입력:
      <!-- TODO -->
    - 출력:
      <!-- TODO -->
    - 완료 판정:

    ```bash
    {{VERIFY}}
    ```

    ## 워크트리

    - 경로: `{{WORKTREE_PATH}}`
    - 브랜치: `{{BRANCH}}`
    - 기준: `origin/main` (로컬 `main/` 에 커밋하지 않는다)

    ## 열린 질문

    <!-- TODO: 구현 전에 잠가야 하는 결정만 -->
    """

    static let agentsTemplate = """
    # 이 방 브리프 — {{ROOM_SLUG}}

    함대 규율은 레포 루트 `AGENTS.md` (`.agents/AGENTS.md` 심링크)다. **이 파일은 이 방만** 말한다.

    ## 할 일

    {{TASK}}

    ## 작업 디렉터리

    ```
    {{WORKTREE_PATH}}
    ```

    이 경로 밖에서 쓰지 않는다. 방 폴더 MD(`ROOM.md` · `DESIGN.md` · 이 파일)만 예외다.

    ## 판정

    ```bash
    {{VERIFY}}
    ```

    exit 0 아니면 끝난 게 아니다.

    ## 쓰지 말 것

    - `scripts/*.sh` 실행·신설
    - 레포 루트 `AGENTS.md` 덮어쓰기
    - `git worktree` 직접 호출 → `agent-worktree-control-terminal`
    - 방 원장 JSON 손수정 → `agent-work-todo`
    - 병렬 `app-build-manager ship` (다건은 ship-queue)
    - 사용자 `ship` 지시 전에 `/Applications` 설치

    ## 물어보기

    ```bash
    agent-room-worktree show --room {{ROOM_ID}}
    agent-work-todo placement show {{PLAN_ID}} --json
    agent-worktree-control-terminal list {{REPO}}
    ```
    """
}
