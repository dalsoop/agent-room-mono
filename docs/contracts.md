# 계약

이 저장소가 밖에 내놓는 인터페이스는 PATH CLI 넷, 방 터미널 데몬 소켓, 방 폴더 파일 구성, StateMirror 파일이다. 라이브러리 킷의 공개 API는 이 저장소 안 앱만 쓴다.

## 공통 규약

- 모든 CLI는 `help`·`version`·`capabilities`를 가진다. `capabilities`는 표준 출력에 `{"ok": true, "result": {"name", "cli", "commands": [{name, summary, json, dryRun?}], "state": [{path, what}], "health": {command, freshness}, "depends": [{id, kind, ref, required, why}]}}`를 낸다. 소비자는 이 출력으로 명령 목록과 의존을 읽는다.
- 종료 코드: 0 성공, 1 실패, 64 사용법 오류. `agent-room-terminal check`의 차단은 2, 설치본이 낡고 `SWIFT_APP_FAIL_CLOSED_STALE=1`이면 70.
- 설치본이 소스보다 낡았으면 stderr에 경고 한 줄이 붙는다(`--json`이 있으면 붙지 않는다). 표준 출력은 건드리지 않는다.
- 사람용 출력과 JSON 출력의 형식은 CLI마다 다르다. 아래 각 절의 형식을 따른다.

## `agent-room-terminal`

출력은 늘 InteropKit 봉투다. 성공은 표준 출력에 `{"ok": true, "result": …}`, 실패는 표준 오류에 `{"ok": false, "error": {"message": "<메시지>"}}`와 종료 코드 1(사용법은 64). `--execute`가 필요한 명령은 없이 부르면 `{"dryRun": true, "command", "roomID", "steps": [...]}` 계획만 내고 부수효과가 없다.

| 명령 | 입력 | 출력 `result` | 오류 |
|---|---|---|---|
| `open <방id> [--spec 파일] [--preset readOnly\|toolbelt\|open] [--tool claude\|codex\|grok\|agy] [--successor] [--execute]` | 방 id 또는 스펙 파일 | `roomID`, `path`, `sessionID`, `sessionRole`, `reused`, `preset`, `tool`, `wallMode`, `seatbelt`, `network`, `linkedTools`, `excludedTools`, `credentialSeed`(`notApplicable`\|`seeded`\|`failed`), `unseedOnClose`, `verdictRunnable`, `roomMarkdown` | `room-id not found: <id>`, 데몬 접속 실패, 방 조립 실패(자식이 부모보다 넓음 등) |
| `open --attach-session <세션id> [--room <id>]` | 이미 도는 세션 | 세션을 방 벽에 등록한 결과(PTY를 새로 만들지 않는다) | 알 수 없는 세션 |
| `close <방id> [--execute]` | 방 id | `roomID`, `closed: true`, `dryRun: false`, `ledgerVacate`, `ledgerRetries`, 인지 원장이 있으면 `cognitiveVerdict`·`cognitiveDriftScore` | `room folder not found under ~/.tenants: <id>` |
| `exec <방id> [--raw] [--tool …] [--timeout N] -- <명령…>` | argv | `exit`, `exitCode`, `stdout`, `stderr`, `timedOut`, 잘렸으면 `truncated: true` | `foreignRoom`, seatbelt 프로필 없음(exit 126 결과), 방 세션 없음(`--raw`) |
| `snapshot <방id> [--lines N]` | | `roomID`, `lines: [String]` | |
| `tree [--tenant T] [--json]` | | 방 목록(빈병 사슬·예산·점유자·프리셋) | |
| `budget <방id> --json` | | `window`, `trigger`, `initialInput`, `reservedOutput`, `usable`, `used`, `handoffAt`, `elapsedMinutes`, `estimatedWorkMinutes`, `state`(`ok`\|`handoff-due`\|`over`\|`unknown`) | |
| `check --cmd "…" [--session id] [--tool 도구]` | 훅이 넘긴 명령 | 통과 exit 0, 차단 exit 2와 stderr의 이유. `ROOM_ID`가 없으면 항상 0 | |
| `daemon start\|stop\|status\|sessions` | | status: `running`, `generation`, `socket`, 돌고 있으면 `pid`·`binaryPath`·`startedAt`. stop: `stopped`, `forced`, `pid` | |
| `events <방id>` · `launch-log <방id>` | | 방 `events.jsonl`·`launch.log` 줄 | |
| `handoff` · `simulate` · `habit` · `usage` · `tuning` · `doctor` · `smoke` · `profile-lock` · `checkpoint` · `runs` · `precompute` · `delta` · `synapses` · `open-gui` | `<명령> --help` | `capabilities`의 `summary` | |

## `agent-room-monitor`

출력은 봉투 없는 JSON(키 정렬, 날짜 ISO 8601)이다. `capabilities`만 봉투다.

| 명령 | 출력 | 오류 |
|---|---|---|
| `snapshot --json` | `TwinSnapshot` 전체: `root`(TwinNode 트리), `flows`, `telemetry`, `trace`, `generatedAt`, `tenants`, `currentTenantID`. 실패한 공급 CLI마다 `root.health.notes`에 한 줄이 붙고 `root.state`가 `block`이 된다 | 없음. 공급 CLI 실패는 `root.health.notes`로만 나타난다 |
| `status --json` | `{rooms, executing, blocked, gates, skills, sessions}` | |
| `telemetry --json` | `{load1, ncpu, memUsedGB, memTotGB, intNetOK, extNetOK}` | |
| `views --json` | 뷰 정의 목록. 비어 있으면 기본 다섯 개를 만든 뒤 돌려준다 | 깨진 뷰 파일은 건너뛰고 stderr에 알린다 |
| `compare --json` | 최근 두 스냅샷의 차이(생긴·사라진·상태 바뀐 노드). 스냅샷이 하나뿐이면 빈 차이 | 보관 실패는 stderr 경고 |
| `trace [--room ID] --json` | 방 단위 이벤트 배열. `--room`이면 그 방과 방 미지정 이벤트 | |
| `ax --app <이름> --json` | `{ok: "true"\|"false", app, text}` | |
| `mutate <조작> …` | `{ok, command, stdout, stderr, exitCode}`. `ok`가 false면 CLI 종료 코드 1 | 인자 부족은 stderr 사용법 한 줄과 exit 64 |
| `agent` · `skill` · `chat` | 공용 에이전트 CLI(AgentCLIKit) 하위 명령 | |

`mutate`의 조작과 실제로 부르는 명령:

| 조작 | 실행 |
|---|---|
| `spawn-room --task --verify --handle --occupant --tenant [--workdir] [--tool]* [--write]*` | handle 검사 → 방 보관함 폴더 준비 → `agent-work-todo placement spawn-room … --via agent-room-monitor` |
| `occupy <plan> <room> --occupant A` | `agent-work-todo placement occupy <plan> <room> --occupant A` |
| `tick <plan> [--workdir P]` | `agent-work-todo placement tick <plan> [--workdir P]` |
| `demolish <설계도slug>` | `agent-work-todo room rm <slug>` |
| `reject <plan>` | `agent-work-todo placement reject <plan> --by agent-room-monitor --reason "room-monitor demolish" --json` |
| `handoff-pack <세션>` · `handoff-resume <세션> --to 도구` | `agent-handoff pack …` · `agent-handoff resume … --to …` |
| `open-skill <이름>` | `open ~/.codex/skills/<이름>/SKILL.md` |
| `seal` · `archive` · `promote-skill` · `search-memory` | 외부 명령 없이 방 보관함을 직접 다룬다. `stdout`에 결과 JSON |

## `agent-room-isolator`

사람용 출력이 기본이고 `--json`이면 봉투(`{"ok": true, "result": …}`)다. 실패는 `--json`이면 표준 출력에 `{"ok": false, "error": {"message": "…"}}`, 아니면 표준 오류에 메시지 한 줄이고 종료 코드 1이다. 필수 인자가 없으면 exit 64다. `capabilities`의 이름은 `agent-room-worktree`다.

| 명령 | 입력 | 출력 `result` |
|---|---|---|
| `provision --task T --verify V --repo P --tenant ID [--occupant A] [--name N] [--quote Q] [--network] [--no-spawn] [--dry-run] [--json]` | | `{dryRun, bind, documents: [경로], planned: [명령]}` |
| `bind --room --worktree --branch --repo --tenant [--plan] [--slug] [--task] [--verify]` | | 저장된 결속 |
| `emit-md --room ID` | | `{documents: [경로]}` |
| `list` | | 결속 배열 |
| `show --room ID` | | 결속 하나 |
| `trace --room ID` | | `{bind, ledger: {ok, planID, roomID, state, occupant, error}, worktree: {pathExists, listedByGit, markerOK, branch}, documents: [{name, path, exists, preview}], ok}`. `ok`가 false면 exit 1 |
| `doctor` | | `{ok, bindCount, findings: ["missing-worktree:<id>" \| "git-unlisted:<id>" \| "missing-marker:<id>" \| "missing-ledger:<id>:<이유>" \| "missing-md:<id>:<파일>"]}`. `ok`가 false면 exit 1 |
| `status` | | `{status: "binds:<수>"}` |

결속 객체: `roomID`, `planID`, `slug`, `task`, `verify`, `worktreePath`, `branch`, `repoPath`, `tenantID`, `createdAt`(ISO 8601).

오류 메시지: 빈 task, 판정 없는 verify(`true`·`:`·`exit 0`·`echo ok`), 결속 없음, 워크트리 생성 실패(하위 명령의 stderr), `spawn-room json missing roomID/planID`.

## `room-release-manager`

사람용 텍스트 출력이다. 설치본 CLI 식별자는 `party-room-release-manager`(사용법·버전·`capabilities`)이고 PATH 이름은 `room-release-manager`다.

| 명령 | 출력 | 오류 |
|---|---|---|
| `status` | 요약 한 줄, `path:`, 플랫폼별 `✓`/`·` 줄 | |
| `probe [--json]` | `--json`이면 `{path, healthy, summary, flutter, gh, artifacts: {android, macos, windows, ios}}` | 모르는 옵션 exit 64 |
| `build <android\|macos\|windows\|ios>` | 빌드 로그. 성공 0, 실패 1 | 모르는 플랫폼 exit 64, 프로젝트 없음, flutter 없음 |
| `release-hint` | `gh release create …` 초안 | |
| `open-project` · `open-artifacts` | Finder를 연다 | |
| `config path <dir>` · `config repo <owner/name>` | 설정 저장 | |

## 데몬 소켓

- 보안 이슈 있음, 비공개 추적. 데몬은 사용자 전용 유닉스 소켓 하나로만 요청을 받고, 세부 프레임·권한 형식은 이 저장소에 공개하지 않는다.

## 방 폴더

`~/.tenants/<테넌트 슬러그>/rooms/<방id>/`(자식 방은 부모 폴더의 `children/<slug>/`):

| 경로 | 쓰는 쪽 | 내용 |
|---|---|---|
| `spec.json` | 방을 만드는 쪽(외부 원장의 방 생성, 운영자). 격리기는 읽기만 하고, 터미널은 인계(`handoff`) 때 `handoverState`·후임 필드만 고쳐 쓴다 | 방 입력(테넌트, task, verdict, workdir, 벽, toolbelt, 허용 도구, 프리셋) |
| `events.jsonl` | 터미널 | 한 줄 한 사건 `{seq, at, kind, actor, payload}`. 조립 `assembled`, 점유 `occupied`, 닫기 `vacated`·`closed` |
| `ROOM.md` · `env` · `bin/` · `work/` · `state/` · `children/` · `handoff/` · `habits/` | 터미널 | 조립문, 세션 env, 심링크, 작업 공간, 로그·사용량·노트·도구 config, 자식 방, 빈병, 습관 |
| 도구 인증 사본 | 터미널 | 보안 이슈 있음, 비공개 추적. 방을 닫으면 지워진다 |
| `bind.json` · `DESIGN.md` · `AGENTS.md` · `worktree` 심링크 | 격리기 | 결속 표지, 방 설계 문서, 방 작업 규칙, 워크트리 링크 |

기본 셸 폴더 `~/.tenants/_base-bin/`에는 POSIX 도구 아홉 개와 `agent-room-terminal`의 심링크만 있다.

## StateMirror

`~/.swift-app-state/<이름>.json`(이름: `agent-room-terminal`, `agent-room-monitor`, `agent-room-worktree`, `party-room-release-manager`). 덮어쓰기 파일이고 `updatedAt`을 포함한다. 관측용 사본이라 정본으로 읽지 않는다.

헬스 펄스는 `~/.swift-app-state/pulse/<이름>.pulse`다(`SWIFT_APP_STATE_ROOT`가 있으면 그 루트 아래). `agent-room-terminal` GUI, `agent-room-worktree`(격리기 GUI), `party-room-release-manager`(GUI 시작과 CLI 실행마다)가 쓰고, 관측판은 쓰지 않는다.
