# 0005. 격리기는 git 워크트리와 원장을 소유 CLI에 맡긴다

**상황**: 격리기(`agent-room-isolator`)는 방 하나에 git 워크트리 하나를 결속하고 원장에 방을 연다. git 워크트리와 방 원장에는 이미 소유 앱이 있다(`agent-worktree-control-terminal`, `agent-work-todo`).

**결정**: 워크트리 생성은 `agent-worktree-control-terminal create <repo> <slug> --inside --base origin/main`, 방 개설은 `agent-work-todo spawn-room --waiting --workdir <워크트리>`로 한다. 격리기는 두 명령의 결과를 결속(`binds.json`, 방 `bind.json`)과 방 문서로 남기고, 확인(`trace`·`doctor`)에서만 `git worktree list --porcelain`을 읽는다. `interop-expects.json`에 "git/원장을 이 앱이 재구현하지 않는다", "git worktree 직접 호출 금지"로 적혀 있다. 원장이 방 id를 돌려주지 않으면 결속을 만들지 않는다(1.0.0, 2026-09-13).

**대안**: 격리기가 `git worktree add`와 원장 파일 쓰기를 직접 하는 것. 소유 앱과 같은 로직을 두 벌 두게 되어 택하지 않았다.

**결과**: 두 CLI가 PATH에 없으면 `provision`이 실패한다(`--dry-run`은 외부 명령을 부르지 않는다). 워크트리 경로 규칙(`<repo>/.worktrees/<slug>`)은 `agent-worktree-control-terminal`의 `--inside` 규칙에 묶여 있다.
