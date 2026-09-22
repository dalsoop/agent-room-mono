# 계약

## CLI `agent-room-terminal`

공통: 출력은 `{"ok": true, "result": …}` 또는 `{"ok": false, "error": "…"}`. 조회는 `--json`. 부작용 명령은 `--execute` 없이는 계획만 출력한다. exit 0 성공, 1 실패, 2 `check` 차단, 64 사용법.

| 명령 | 입력 | 출력 result | 오류 |
|---|---|---|---|
| `open <방id> [--preset readOnly\|toolbelt\|open] [--tool claude\|codex\|grok\|agy] [--successor] [--execute]` | 원장 방 id | `{roomDir, sessionID, preset, tool, sessionRole: predecessor\|successor, predecessorSession?, excludedTools[], assembly(ROOM.md 본문)}` | 방 없음 · 미준수로 toolbelt 전부 배제 · 데몬 접속 실패 |
| `close <방id> [--execute]` | | `{sessionID}` | 알 수 없는 세션 |
| `exec <방id> -- <명령…>` | argv | `{exitCode, stdout, stderr}` | foreignRoom |
| `tree [--tenant T] [--json]` | | `{rooms:[{id, slug, tenant, state, preset, wallMode, occupant, successorOccupant, handoverState, budget, excludedTools, handoffChain:[…], children:[…]}]}` | |
| `snapshot <방id> [--lines N]` | | `{lines:[String]}` | |
| `check --cmd "…" [--session id] [--tool 도구]` | 훅 stdin/인자 | exit 0 통과 · 2 차단(stderr 이유). `ROOM_ID` 없으면 항상 0 | |
| `budget <방id> --json` | | `{window, trigger, initialInput, reservedOutput, usable, used, handoffAt, elapsedMinutes, estimatedWorkMinutes, state}` | |
| `handoff <방id> --note "…" [--amend id] [--execute]` | | `{handoffID, predecessor, successorSession, tool}` | |
| `simulate <방id> --against <빈병id> --json` | | `{passed, steps:[{habit (argv 요약), step, mode: executed\|compared\|skipped, ok, reason}], verdictMatched, reason?}` 후보 0 이면 `{passed: true, steps: [], reason: "no-habits"}`. 재연: 에이전트 CLI(claude·codex·grok·agy)는 `skipped`·ok=true·reason `"agent command — not replayed"` (실행 금지). dry-run 계약(`--dry-run` 을 받거나 capabilities `dryRun: true`)이면 `executed`(dry-run 실행, exit 0 이면 ok). 계약 없으면 `compared`(argv 첫 토큰이 방 `bin/` 에 링크돼 있고 `--help` 가 exit 0 이면 ok). `passed` = skipped 를 뺀 항목이 전부 ok. 실패 항목은 reason 필수. | |
| `habit list <방id> [--candidates] --json` / `habit note <방id> --deviated N --reason "…"` / `habit promote <방id> N\|--from-candidates [--execute]` | | `{habits, candidates}` / `{notePath}` / `{wikiCandidate, wikiReceipt}` 또는 `{promoted}` | 승격 조건 미달 |
| `daemon start\|stop\|status [--json]` | | `{running, generation, socket}` | |
| `usage <방id> --json` | | `[{ts, tool, inputTokens, outputTokens, requests}]` | |
| `tuning show\|set <키> <값>` | | 7키 값 | 모르는 키 |
| `capabilities` | | commands·depends·stateRoot 선언 | |

## 훅 규칙 (agent-guardrail-manager 가 심는다)

- `roomWall` PreToolUse(Bash): `ROOM_ID` 가 있으면 `agent-room-terminal check --cmd "$cmd" --session "$ROOM_SESSION"` 의 exit 를 그대로 낸다.
- `roomChild` PreToolUse(Agent): `ROOM_ID` 가 있으면 `check --tool Agent` → 방 안이면 exit 2.
- `roomAssembly` SessionStart: `ROOM_ID` 와 `$PWD/ROOM.md` 가 있으면 그 파일을 출력한다.
차단 규칙: 절대경로 실행(첫 토큰 또는 `;`·`&&`·`|` 뒤 토큰이 `/` 로 시작), `env PATH=`, `sh -c`, `bash -c`, `zsh -c`, `python3`.

## 데몬 소켓

경로 `~/.tenants/_daemon/agent-room-terminal.sock`(0600). 프레임 = 4바이트 big-endian 길이 + JSON. 요청 필드: `op`(openSession·closeSession·exec·attach·snapshot·listSessions·tuning·input), `roomDir`, `envFile`, `shell`, `seatbeltProfile`, `sessionID`, `argv`, `lines`, `tuningAction`·`tuningKey`·`tuningValue`, `input`/`bytes`, `authority`("commandRoom"), `roomSession`(요청자 세션). 응답: `{ok, result, error, generation}`; attach 스트림은 이어서 `{event: "output", sessionID, bytes(base64)}` 와 `{event: "exit", sessionID, code}`.
- `openSession` 은 지휘실 권한 필수. 요청 `sessionRole`(predecessor|successor, 생략 시 predecessor). result `{sessionID, pgid}`. `listSessions` 항목에 `sessionRole`. 한 방에 전임·후임 세션 둘을 허용한다.
- `exec` result `{exitCode, stdout, stderr}`(세션 env·seatbelt 적용).
- `snapshot` result `{lines}`. `listSessions` result `{generation, sessions:[…]}`.
- 인가 실패는 `error: "foreignRoom"`, 세션 없음은 `"unknown session"`.

## 방 폴더

`~/.tenants/<슬러그>/rooms/<배치도id>/<방slug>/`: `ROOM.json`(0444: blueprint 스냅샷·state·preset·budget·excludedTools) · `ROOM.md` · `bin/`(심링크) · `env`(KEY=VALUE) · `work/` · `state/term.log`·`state/usage.jsonl`·`state/notes/` · `children/<자식slug>/` · `handoff/<id>.json`(habitCandidates) · `habits/<번호>-<slug>.habit.json`·`habits/INDEX.md`·`habits/candidates.jsonl`. 기본 셸 폴더 `~/.tenants/_base-bin/`(심링크 10개).

## 원장 필드 (정본 apps/agent-work-todo)

설계도 `wallPreset`(readOnly|toolbelt|open, 기본 toolbelt) · `agentTools`(기본 claude·codex·grok·agy). 방 `wallMode`(full|hookOnly) · `successorOccupant` · `successorSession` · `handoverState`(none|simulating|passed|failed). 빈병 `predecessor`(UUID?) · `budget{window, trigger, initialInput, reservedOutput, usable, used, handoffAt, elapsedMinutes, state}` · `tool`. CLI: `placement occupy --successor --wall-mode`, `placement handover <plan> <room> --state`.

## 테넌트 준수 (정본 apps/agent-tenant-isolation-manager)

`check <cli> --json` → `{compliant, reason, method: capabilities|probe}`. 준수 = capabilities `stateRoot.env == "SWIFT_APP_STATE_ROOT"` 선언, 또는 그 env 를 임시 폴더로 준 `status --json` 이 그 폴더에 파일을 만듦. `world ensure <tenant> [--execute]` → tenant world 생성·등록·정책 wikiWorld 갱신.

## 위키 층 (정본 agent-wiki-kit·agent-wiki-global·agent-wiki-local)

`world add <이름> <경로> --layer tenant --parent gujo-wiki`, `world set-layer`. 인용은 상위 world 만 허용, 형제·하위 인용 거부. `context`·`search` 는 자기+상위. `promotion publish <id> --to <상위world> --confirm`. `AGENT_WIKI_WORLD` 가 있으면 다른 `--world` publish 거부.
| `handoff <방id> --note "…" [--amend id] [--execute]` | | 빈병 JSON(`readDocuments`·`executedCommands`·`producedFiles`·`lastAssistantText`·`evidenceSource` 옵셔널) | |
| `handoff <방id> --show <빈병id>` | | 사람용 마크다운(결론→문서→산출물→명령→함정→습관). `--json` 이면 빈병 JSON | 빈병 없음 |
