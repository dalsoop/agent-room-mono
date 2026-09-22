# 미해결

## 원장에 빈병 digest 전용 쓰기 명령이 없다

- 조건·증상: `handoff` 가 `HandoffDigest`(predecessor·budget·tool)를 원장에 남기려 하지만 agent-work-todo CLI 에 digest 를 직접 쓰는 명령이 없어, 원장에는 `occupy --successor` 만 가고 digest 본문은 방 `handoff/<id>.json` 파일에만 있다.
- 영향: 빈병 사슬을 원장만 보고는 알 수 없다. `tree` 는 방 파일을 읽어 사슬을 만든다.
- 왜 지금 못 고치나: agent-work-todo 에 새 CLI 명령(예 `placement handoff-record`)이 필요하고 별도 MR 이다.
- 접근: agent-work-todo 에 `placement handoff-record <plan> <room> --file <digest.json>` 을 더하고 `HandoffLedgerPort` 가 그것을 부르게 한다.

## 원본 브랜치 병합 시 seat-manager 정리 필요

- 조건·증상: `origin/feat/mac-remote-bottleneck-kernel-diagnosis` 가 병합되면 agent-seat-manager 에 `room enter/exec/promote/discard`·`RoomOps`·`RemoteRoomRunner`·SandboxKit 의존이 다시 들어와 이 앱의 `Core/Room/RoomOps` 와 중복된다(code-clone-stamp).
- 영향: 그 병합의 커밋 게이트가 막힌다.
- 왜 지금 못 고치나: 그 브랜치는 이 바퀴 밖이다.
- 접근: 병합 전에 seat-manager 쪽 room 명령과 파일을 지운다.

## Antigravity 사용량은 항상 unknown

- 조건·증상: Antigravity 세션 저장소에 토큰 사용량 컬럼이 확인되지 않아 어댑터가 unknown 만 낸다. 시간 축만으로 handoff-due 가 판정된다.
- 영향: Antigravity 방은 토큰 초과를 못 잡는다.
- 왜 지금 못 고치나: 저장소 스키마 실측이 필요하다.
- 접근: 세션 sqlite 를 열어 usage 필드를 찾고 어댑터를 채운다.

## 훅 규칙은 만들었지만 사용자 설정에 적용되지 않았다

- 조건·증상: agent-guardrail-manager 에 roomWall·roomChild·roomAssembly 규칙이 있으나 `apply` 를 치지 않아 `~/.claude/settings.json` 에는 없다.
- 영향: 방에 앉은 Claude Code 세션의 훅 벽(보조)이 아직 서지 않는다. 세 겹 벽은 훅과 무관하게 선다.
- 왜 지금 못 고치나: 사용자 설정 변경은 사용자가 지시할 때만(설정 변경은 diff 사전 공지 후 실행).
- 접근: `agent-guardrail-manager apply --dry-run` 으로 diff 를 보이고 승인 뒤 `apply`.

## (수리됨 2026-09-03 저녁) close 가 원장 자리를 비우지 않던 것 → `placement vacate`·`instantiate-due` 건너뜀

- 조건·증상(실측 2026-09-03): `close --execute` 뒤에도 원장 방은 `occupied` 로 남는다(원장에 vacate 가 없고 tick 만 간다). 같은 시각 `placement instantiate-due`(상주 설계도 감시기)가 gujo 설계도를 다시 구체화해 배치도 id 가 바뀌고, 지휘실이 연 방 폴더 4개가 다른 3개로 교체됐다.
- 영향: 같은 신원이 다시 방을 열려면 배치도를 폐기해야 한다. 화면의 방 목록이 사용자가 연 것과 다르게 바뀐다.
- 수리: agent-work-todo 1.19.3 에 `placement vacate`(occupied→waiting) 추가, `instantiate-due` 는 같은 설계도의 approved|executing 배치도가 있으면 건너뛴다. 남은 것: `close --execute` 가 vacate 를 자동으로 부르는 배선(다음 바퀴). 방 폴더 교체의 실제 원인은 다른 세션의 worktree 아카이브였다(아래 항목).

## 예산 게이지가 전부 unknown

- 조건·증상: 사용량 어댑터가 도구 세션 로그를 못 찾아 `budget.state == unknown`. 핸드오프가 자동으로 발동한 사례가 0건.
- 영향: "토큰 넘으면 핸드오프" 가 시간 축으로만 판정된다.
- 접근: 방 `state/` 에 도구별 전사 경로를 고정하고 데몬이 tail 해 used 를 산출(참고 agent-dashboard 의 JSONL 전사 파싱). 백로그 c82ddd95.

## (수리됨 2026-09-05) 앱이 문서 폴더 접근 권한을 요청한다

- 조건·증상: 개발 번들로 띄운 GUI 첫 실행에서 macOS 가 "문서 폴더의 파일에 접근" 권한 팝업을 띄웠다.
- 원인 규명: AppScaffoldKit 이 아닌 `RoomFolderLocator.walk` 에서 발생. `fm.enumerator(at: ~/.tenants, includingPropertiesForKeys: [.isDirectoryKey])` 로 `~/.tenants` 전체를 전수 재귀 순회하면서 `personal/skills/*` 및 방 내부 `bin/*` 에 존재하는 작업트리/문서 폴더(`~/Documents/...`) 심링크 대상에 대해 `.isDirectoryKey` 판정을 수행하여 macOS TCC 문서 폴더 권한 팝업이 유발됨.
- 수리(2026-09-05): `RoomFolderLocator.walk` 를 리팩토링하여 비방 디렉터리(`_base-bin`, `_daemon`, `skills`, `wiki`, `Library` 및 방 내부 `bin/`, `work/`, `state/`)를 전수 순회하지 않고 오직 `~/.tenants/<tenant>/rooms/<layoutID>/<roomSlug>` 및 `children/` 계층만 직접 탐색하도록 스캔 범위를 엄격히 한정. 심링크 역참조 및 Documents 접근 원천 차단. 백로그 `C6AF5345-E237-4E95-9222-EB7098CC488B`.

## 작업 트리가 다른 에이전트 세션의 아카이브 작업에 통째로 삭제됐다 (2026-09-03 21:00)

- 조건·증상: 다른 AI 세션(agy)이 `.worktrees/<이름>` 을 NAS 로 tar 한 뒤 `rm -rf` 하는 작업을 돌렸고, 활성 작업 트리 `dryforge-agent-room-terminal` 이 대상에 들었다. 진행 중 파일이 사라지며 빌드가 깨졌고, 처음엔 방 감시기(tick) 철거로 오인했다.
- 영향: 미커밋 W5 산출·`.dryforge/`(설계 3문서·프롬프트·결과) 손실 → 브랜치에서 worktree 재생성 + tar 에서 `.dryforge` 추출로 복구. 커밋은 전부 보존.
- 왜 지금 못 고치나: 이 앱 밖(호스트 운영). 재발 방지는 아카이브 도구가 `git worktree list` 의 활성 트리(다른 세션 cwd 가 안에 있는 것)를 건너뛰게 하는 것.
- 접근: 방 체제로 보면 "방 밖에서 일하는 에이전트" 가 남의 방 폴더를 지운 사건이다. 방 폴더에 대한 삭제는 방 주인(원장 착석자)만 할 수 있어야 한다 — ExecPolicy quarantine 이 `rm -rf` 를 잡는 이유.

## 데몬 exec 거부 사유가 "DaemonProtocolError error 0" 으로 뭉개짐

- 수리(같은 날): `DaemonProtocolError` 에 `LocalizedError` 채택 — 데몬 사유가 그대로 보인다.

## 예산 unknown 은 전사 등록(`state/transcripts.json`) 전까지 유지

- 조건: W3 가 `TranscriptRegistry.register` 공개 API 만 만들었고, 세션이 열릴 때 도구 전사 경로를 등록하는 CLI 배선은 다음 바퀴다.
- 접근: `open` 이 tool 에 따라 전사 경로 규칙(claude `~/.claude/projects/<slug>/`)을 등록하고, 데몬이 tail.
