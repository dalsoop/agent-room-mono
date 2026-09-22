# 구성

## 네 면과 그 사이

```
사용자 / 세션
  │ 클릭·컨텍스트 메뉴                 │ 명령
  ▼                                   ▼
GUI (AgentRoomTerminal)          PATH CLI (agent-room-terminal, Foundation 만)
  └── Core 호출                        └── Core 호출
        │                                    │
        ▼                                    ▼
      Core (AgentRoomTerminalCore) — Room · Daemon(클라이언트) · Ledger · Budget · Habit · Terminal(모델) · Canvas(순수 계산) · Tuning
        │ 유닉스 소켓 (길이 접두 JSON 프레임)             │ CommandKit 으로 CLI 호출
        ▼                                                ▼
실행 데몬 (agent-room-terminal-daemon)          외부 앱: agent-work-todo(원장) · agent-room-monitor(방 생성)
  PTY(SwiftTerm LocalProcess) · 세션 표 · 인가 ·     agent-tenant-isolation-manager(정책·준수) · agent-wiki(승격)
  링 버퍼 · 유휴 종료 · 원장 직렬 큐
        │ zsh -r + sandbox-exec
        ▼
방 폴더 ~/.tenants/<테넌트>/rooms/<배치도>/<방>/  (ROOM.md · bin/ · env · work/ · state/ · children/ · handoff/ · habits/)
```

- GUI 와 CLI 는 Core 의 같은 진입점을 부른다. 둘 중 하나에만 있는 기능은 없다(4면 계약). GUI 는 부작용 액션 앞에 확인 시트를 한 번 띄운다.
- Core 는 파일 시스템(방 폴더, AppPaths 상태 경로)과 소켓 클라이언트만 가진다. AppKit·SwiftTerm 을 import 하지 않는다.
- 데몬은 PTY 와 프로세스 그룹의 유일한 소유자다. 앱·CLI 가 죽어도 세션은 살고, 마지막 세션이 닫힌 뒤 유휴 시간(기본 60초)이 지나면 데몬이 스스로 끝난다. 상주 등록(LaunchAgent)은 없다.
- 외부 앱은 CLI 로만 부른다. 그 앱들의 상태 파일 경로는 이 앱 어디에도 없다.

## 대표 흐름 — 방 열기

1. CLI `open <방id> --execute` 또는 GUI "열기".
2. Core Ledger 가 `agent-work-todo placement list --json` 으로 방·설계도·벽을 읽는다(설치본 경고가 앞에 붙어도 첫 `{` 부터 파싱).
3. Core Room 이 `agent-tenant-isolation-manager check <cli> --json` 으로 toolbelt 각 앱의 테넌트 준수를 판정하고, 방 폴더를 멱등 조립한다(ROOM.json·ROOM.md·bin 심링크·env·work·state·children·handoff·habits). 미준수 앱은 `excludedTools` 에 남는다.
4. Core Daemon 클라이언트가 소켓에 `openSession{roomDir, envFile, shell, seatbeltProfile}` 을 보낸다. 소켓이 없으면 데몬 실행 파일을 띄우고 재접속한다.
5. 데몬이 새 프로세스 그룹에서 `zsh -r`(open 프리셋은 `zsh`)을 PTY 로 띄우고 세션 id 를 발급한다. env 파일의 `PATH` 는 방 `bin/` 과 기본 셸 폴더뿐이다.
6. Core Ledger 의 직렬 큐가 `placement occupy … --wall-mode full` 을 원장에 기록한다(occupantSession = 세션 id).
7. 조립문(ROOM.md)이 출력되고 세션이 그 안에서 시작한다. 에이전트 도구(claude·codex·grok)는 그 세션 셸에서 사용자가 띄운다.

## 대표 흐름 — 세대 교체

세션의 훅이 매 턴 `budget` 을 읽어 `handoff-due` 면 세션이 `handoff` 를 친다 → Core Budget 이 빈병 파일과 원장 `HandoffDigest`(predecessor·budget·tool)를 만들고 후임을 `occupy --successor` 로 앉힌다(handoverState = simulating, 전임 생존) → 후임이 `simulate` 로 최근 습관을 재연한다 → 통과면 데몬이 전임 세션을 종료하고 원장 `handover --state passed`, 실패면 `failed` 와 빈병 보강 요구.

## 모듈 지도

| 모듈 | 역할 | 의존 방향 |
|---|---|---|
| Core/Room | 방 폴더 조립·프리셋 bin·env·준수 게이트·자식 상속 검사, 이관된 RoomOps(샌드박스 보관·승격) | swiftkit SandboxKit·RoomWallKit·StateRootKit → |
| Core/Daemon | 소켓 프로토콜 타입·프레이밍·클라이언트·세션 인가 규칙 | Foundation 만 |
| Core/Terminal | 세션 모델·링 버퍼(파서는 데몬 쪽) | Foundation 만 |
| Core/Ledger | 단일 직렬 큐, 원장·방 생성 CLI 호출, 타 방 거부 | CommandKit → |
| Core/Budget | 도구별 창 규격·예산 계산·사용량 어댑터 4종(전사 파일 직접 읽기)·사용량 원장·핸드오프·도구 선택 | Foundation 만 |
| Core/Habit | 습관 파일·INDEX·이탈 노트·시뮬레이터·자동 승격 | Core/Daemon, Core/Ledger → |
| Core/Canvas | 층 배치·LOD 판정·상태색(순수 계산) | Foundation 만 |
| Core/Tuning | 튜닝값 7개 저장소 | AppPaths → |
| Daemon 타깃 | 소켓 서버·PTY 세션·헤드리스 Terminal 파싱·유휴 종료·세대 번호 | Core + SwiftTerm + SandboxKit → |
| GUI 타깃 | CALayer 트리 캔버스·SwiftTerm 오버레이·상세 패널·설정 | Core + SwiftTerm → |
| CLI 타깃 | 서브커맨드 배선·capabilities·훅용 check | Core (Foundation 만) → |

## 외부 의존

swiftkit(SandboxKit·RoomWallKit·StateRootKit·CommandKit·InteropKit·StateMirrorKit·AppPathsKit), SwiftTerm 1.15 이상(데몬·GUI 만), `/usr/bin/sandbox-exec`, `zsh`. 런타임 CLI 의존: agent-work-todo · agent-room-monitor · agent-tenant-isolation-manager · agent-wiki.
