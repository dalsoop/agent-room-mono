# 도메인 규칙

## 용어

- **방(room)**: 에이전트 세션 하나가 일하는 격리 단위다. 식별자는 방 id(원장이 준 UUID 또는 설계도 handle)이고, 테넌트 하나에 속한다. 방은 폴더 하나, 벽 설정 하나, 그 폴더 안에서만 도는 터미널 세션(최대 전임·후임 두 개)으로 이루어진다.
- **테넌트(tenant)**: 상태가 섞이면 안 되는 사용 주체다. id는 `tenant:<슬러그>` 꼴이고 폴더 이름은 슬러그다. 테넌트는 방이 가진 값(`placement.tenantID`, `spec.tenant`)으로 정하며, 자리(seat)나 현재 셸의 테넌트로 덮어쓰지 않는다.
- **벽(wall)**: 방 세션이 쓸 수 있는 실행 파일·쓰기 경로·네트워크의 한계다. 프리셋으로 크게 정하고 방 설정으로 세부를 정한다.
- **toolbelt**: 방 `bin/`에 심링크로 들어가는 CLI 목록이다.
- **handle**: 방을 사람이 읽는 이름이다. 경로 성분으로 쓰이므로 규칙을 통과해야 한다.
- 같은 낱말 "원장"이 두 뜻으로 쓰인다. 격리기·관측판에서 원장은 외부 앱 `agent-work-todo`의 배치 원장이고, 방 터미널에서 방 상태의 정본은 방 폴더의 `events.jsonl`(사건 로그)이다. 방 터미널 코드의 `Ledger*` 이름은 옛 이름이며 외부 원장을 뜻하지 않는다.

## 벽 프리셋

순서는 `readOnly` < `toolbelt` < `open`이다.

| 프리셋 | 방 `bin/` | 셸 | seatbelt | toolbelt 상한 |
|---|---|---|---|---|
| readOnly | 기본 POSIX 아홉 개(`ls cat head tail sed grep find wc git`) + `agent-room-terminal`(준수할 때만) | `zsh -r` | 켬 | 6 |
| toolbelt | readOnly의 것 + toolbelt CLI + 에이전트 도구가 요구하는 도우미(`claude` → `security`) | `zsh -r` | 켬 | 6 |
| open | 심링크 없음(호스트 PATH) | `zsh` | 켬(쓰기 경로만 제한) | 없음 |

- 자식 방의 프리셋은 부모보다 넓을 수 없다. 자식이 부모보다 넓으면 조립 실패다.
- toolbelt가 여섯 개를 넘으면 앞에서부터 여섯 개만 링크되고 나머지는 조용히 빠진다. 여섯 개를 넘는 설계도는 실패하지 않으므로, 뒤쪽 도구가 필요한 방은 설계도에서 순서를 조정해야 한다.
- `python3`, `sh`, `bash`, `env`, `osascript`는 기본 셸 폴더에 넣지 않는다.
- toolbelt CLI가 테넌트 준수 판정(`agent-tenant-isolation-manager check <cli> --json`의 `compliant`)을 통과하지 못하면 어느 프리셋에서도 링크되지 않고 `excludedTools`에 남는다. `agent-room-terminal` 자신도 같은 판정을 받는다.

## 방 열기

- 방 입력은 `--spec <경로>`로 받은 파일이 먼저이고, 없으면 방 폴더의 `spec.json`이다. 둘 다 없으면 열지 않는다(`room-id not found`).
- 도구는 `--tool` 값, 없으면 방의 허용 도구 목록에서 알아보는 첫 값(`claude`·`codex`·`grok`·`agy`), 그것도 없으면 `claude`다.
- 같은 방에 살아 있는 세션이 있으면 새 세션을 만들지 않고 재사용한다(`reused: true`). 한 방에는 역할이 다른 세션 둘(전임 `predecessor`, 후임 `successor`)까지 공존할 수 있다.
- 후임으로 열지는 `--successor` 플래그 또는 방의 인계 상태(`handoverState`)·점유자·후임 점유자·요청 점유자를 함께 보고 정한다.
- 방의 판정 명령(verdict)이 방 안에서 실행될 수 없으면(도구가 toolbelt에 없거나 배제됨) 열기는 계속하고 stderr에 경고 한 줄을 남긴다.
- 점유자 문자열은 `agent:<도구>@<호스트 라벨>`이다.
- 열기의 각 사건은 방 `events.jsonl`에 순서대로 붙는다: 조립되면 `assembled`, 세션이 앉으면 `occupied`. 점유자와 세션 id는 이 로그를 접어서 얻는다.

## 예산

도구별 실효 입력(usable)과 인계 시점(handoffAt)은 다음 식이다. `initialInput`은 방을 열 때 주입한 문서의 토큰 수다.

| 도구 | window | usable | handoffAt |
|---|---|---|---|
| claude | 1,000,000 | ⌊1,000,000 × 0.835⌋ − initialInput | ⌊usable × 0.8⌋ |
| codex | 272,000 | 272,000 − 13,000 − initialInput | ⌊usable × 0.8⌋ |
| grok | 500,000 | ⌊500,000 × 0.8⌋ − initialInput | ⌊usable × 0.8⌋ |
| agy | 200,000 | ⌊200,000 × 0.8⌋ − initialInput | ⌊usable × 0.8⌋ |

usable과 handoffAt은 음수가 되지 않는다(0에서 멈춘다). 국면은 다음 순서로 판정한다.

1. 사용량(`used`)을 모르면: 시간 초과면 `handoff-due`, 아니면 `unknown`.
2. `used ≥ usable`이면 `over`.
3. `used ≥ handoffAt`이면 `handoff-due`.
4. 그 밖에는 시간 초과면 `handoff-due`, 아니면 `ok`.

시간 초과는 경과 분과 예상 분이 둘 다 있고 예상 분이 0보다 클 때 `경과 ≥ 예상 × 3`이다. 인계 제안은 `handoff-due`와 `over`에서만 한다. 도구를 고를 때는 허용 도구 중 잔여(`usable − used`, 사용량을 모르면 `usable`)가 가장 큰 것을 고른다.

## 방 개념과 워크트리 결속 (agent-room-isolator)

- 방은 개념이 먼저다. `task`가 공백뿐이면 거부한다. `verify`가 비었거나 소문자로 바꿔 `true`, `:`, `exit 0`, `echo ok` 중 하나면 판정이 없는 것으로 보고 거부한다.
- 워크트리·브랜치 이름(slug)은 `--name`, 없으면 `task`에서 만든다. ASCII 영문자와 숫자만 남기고 나머지 연속 구간은 `-` 하나로 바꾸며 48자에서 자른다. 결과가 두 글자 미만(한글만 있는 task 등)이면 대체값 `room`을 쓴다.
- 워크트리는 `<repo>/.worktrees/<slug>`에 `origin/main`을 기준으로 만든다. 원장 방 개설(`spawn-room --waiting`)은 워크트리 생성 뒤에 한다. 원장 응답에 `roomID`나 `planID`가 없으면 결속을 만들지 않고 실패한다.
- `--no-spawn`이면 원장을 부르지 않고 방 id와 배치 id를 새 UUID로 만든다. 이 방은 원장에 없으므로 `trace`에서 `missing-ledger`로 잡힌다.
- `--dry-run`이면 외부 명령을 하나도 부르지 않고 계획한 명령과 결속 초안(`roomID: "dry-run"`)만 돌려준다.
- 결속은 두 곳에 같이 남는다: 앱 상태의 `binds.json`과 방 폴더의 `bind.json`. 방 폴더에는 `ROOM.md`·`DESIGN.md`·`AGENTS.md`와 워크트리를 가리키는 `worktree` 심링크가 생긴다. 이미 `worktree`가 있으면 덮어쓰지 않는다.
- `list`는 원장(`agent-work-todo placement list --json`)이 비어 있지 않으면 원장 결과만 쓰고, 원장이 비었거나 실패하면 `binds.json`으로 돌아간다. 방 폴더의 `spec.json`에 `workdir`·`verdict`가 있으면 그 값이 원장 값을 덮어쓰고, `task`는 비어 있을 때만 채운다.
- `trace`가 `ok`인 조건은 워크트리 경로 존재, `bind.json`의 방 id·배치 id·워크트리 경로 일치, 원장 조회 성공, 방 문서 세 개 존재가 모두 참인 것이다. `git worktree list`에 없는 것은 `doctor`의 지적(`git-unlisted`)으로만 나오고 `ok`를 뒤집지 않는다.

## 방 관측과 조작 (agent-room-monitor)

- handle 규칙: 앞뒤 공백을 뺀 값이 비었거나, 40자를 넘거나, `/`·`\`를 포함하거나, `tenant:`로 시작하면 `spawn-room`을 원장에 보내지 않고 거부한다. 결과 JSON의 `exitCode`는 64이고 CLI 종료 코드는 1이다.
- 격리 위험 표시는 선언된 값만 본다(OS 강제가 아니다). 쓰기 경로가 홈 전체(`~`, `~/`, `~/*`, `~/**`, `~/**/*` 등)면 위험, toolbelt 도구가 다섯 개 이상이면 위험이다.
- 조작 시간 제한은 `tick` 180초, `spawn-room` 120초, 그 밖 30초다.
- `seal`·`archive`·`promote-skill`·`search-memory`에서 `--tenant`를 빼면 테넌트는 `default`다.
- 스킬 승격 충돌 정책은 `--auto-bump`가 있으면 자동 버전 올림, 없고 `--force`면 덮어쓰기, 둘 다 없으면 거부다. 대상 폴더를 주지 않으면 `--scope global`은 상태 루트의 `.codex/skills`, 그 밖은 테넌트 상태 루트의 `skills`다.

## 파티룸 배포 (room-release-manager)

- 대상 프로젝트는 설정의 `projectPath`, 기본은 홈 아래 `Documents/WORK/WORKSPACE/apps/flutter-app-mono/main/apps/game-party-room-app`이다. 경로가 없으면 빌드하지 않는다.
- Flutter 실행 파일은 `which flutter`, 없으면 `which fvm`(이때 `fvm flutter …`로 실행), 없으면 Homebrew 경로 순으로 찾는다. 모두 없으면 빌드하지 않는다.
- 모든 빌드는 `flutter pub get`이 성공한 뒤에만 이어진다.
- macOS 빌드는 프로젝트에 `tools/release.sh`가 있으면 그 스크립트(서명·공증·DMG)를 돌리고, 없으면 `flutter build macos --release`를 돌린다. Windows는 이 Mac에서 실패할 수 있다고 로그에 적고 시도한다. iOS는 `flutter build ipa --release`이고 서명 팀이 필요하다.
- GitHub Release는 실행하지 않고 `gh release create` 명령 초안만 준다(저장소 기본값 `dalsoop/party-room`, 태그 기본값 `v1.0.0`).
