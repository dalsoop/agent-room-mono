# 구성

## 패키지 지도

저장소 루트에는 빌드 단위가 없다. 빌드 단위는 여덟 개의 독립 SwiftPM 패키지이고, 서로 상대 경로(`.package(path:)`)로만 연결된다.

```
apps/agent-room-terminal ─┬─→ swiftkit-terminal ──→ swiftkit
apps/agent-room-monitor  ─┤
apps/agent-room-isolator ─┼─→ swiftkit-appscaffold ─→ swiftkit-sparkle ─→ swiftkit
apps/room-release-manager ┘                       └──────────────────→ swiftkit
                          └─→ swiftkit (직접)
apps/agent-room-isolator ───→ ../../Common/{System,CLI,UI}  (이 저장소에 없음)
```

| 패키지 | 역할 | 의존 방향 |
|---|---|---|
| `apps/agent-room-terminal` | 방 폴더 조립, PTY 세션을 쥔 실행 데몬, 방 트리 GUI, PATH CLI | swiftkit · swiftkit-terminal · swiftkit-appscaffold · swiftkit-sparkle → |
| `apps/agent-room-monitor` | 방·자리·스킬·세션·호스트 상태를 다른 앱 CLI에서 모아 한 스냅샷으로 보여 주는 관측판과 방 조작 버튼 | swiftkit · swiftkit-appscaffold · swiftkit-sparkle → |
| `apps/agent-room-isolator` | 방 개념(task·verify) 검증 → git 워크트리 생성 → 원장 방 개설 → 방 폴더 문서 발행 | swiftkit · swiftkit-appscaffold · swiftkit-sparkle · Common(없음) → |
| `apps/room-release-manager` | 파티룸 Flutter 앱(`game-party-room-app`)의 Android·macOS·Windows·iOS 빌드와 GitHub Release 힌트. 방 체제와 무관하다 | swiftkit · swiftkit-appscaffold → |
| `swiftkit` | 공용 킷 244개. 방 체제는 RoomKit·RoomPlacementKit·RoomSeatKit·SandboxKit·StateRootKit·CommandKit·StateMirrorKit·InteropKit·AppPathsKit를 쓴다 | swift-crypto·swift-argument-parser 외 외부 의존 없음 |
| `swiftkit-terminal` | 터미널 엔진 프로토콜(TerminalEngineKit)과 구현 둘(SwiftTerm 1.13.0 고정, libghostty-spm 리비전 고정) | swiftkit → |
| `swiftkit-appscaffold` | 앱 공용 진입 스캐폴드(`RanodeApp`)와 트레잇 세 개(GujoManaged·SelfUpdating·Telemetry) | swiftkit · swiftkit-sparkle → |
| `swiftkit-sparkle` | Sparkle 2 자동 업데이트 래퍼 | swiftkit · Sparkle → |

앱 패키지 하나는 네 면으로 나뉜다: Core 라이브러리(도메인), GUI 실행 타깃, Foundation 전용 PATH CLI 실행 타깃, 그리고 StateMirror 게시(`~/.swift-app-state/<앱>.json`). GUI와 CLI는 같은 Core 진입점을 부른다. `agent-room-terminal`만 네 번째 실행 파일(`agent-room-terminal-daemon`)을 더 가진다.

## 방 체제의 구성 요소

```
운영자 / 지휘 세션
  │ open·close·exec·attach (CLI 또는 GUI)
  ▼
agent-room-terminal CLI·GUI ──(Core: RoomOpenPipeline)──┐
  │                                                     │ 방 폴더 조립(spec.json·env·bin·ROOM.md…)
  │ 사용자 전용 유닉스 소켓                             ▼
  ▼                                          ~/.tenants/<테넌트>/rooms/<방id>/
agent-room-terminal-daemon                      events.jsonl ← 방 사건 원장(assembled·occupied…)
  PTY(SwiftTerm) · 세션 표 · 세션 인가 · 링 버퍼
  │ sandbox-exec -p <seatbelt 프로필> zsh -r
  ▼
방 세션 셸 (방 bin/ 전용 PATH, 프록시 env)

agent-room-isolator ── agent-worktree-control-terminal create … --inside
                   └── agent-work-todo spawn-room --waiting --workdir <워크트리>
                   └── 방 폴더에 bind.json · ROOM.md · DESIGN.md · AGENTS.md · worktree 심링크

agent-room-monitor ── 13개 소유 CLI를 병렬 호출 → TwinSnapshot → HexBoard/FloorGrid·HUD
                   └── mutate: agent-work-todo · agent-handoff · open, 방 보관함(seal·archive·promote·search)은 RoomPlacementKit 직접
```

- `agent-room-terminal`은 이 저장소 판에서 외부 원장 CLI를 부르지 않는다. 방 입력은 방 폴더의 `spec.json`, 점유 상태는 방 폴더의 `events.jsonl`을 `RoomStatusProjection`으로 접어서 얻는다. 코드의 `Ledger*` 이름(`LedgerRoomHit`, `LiveRoomLedgerLookup`)은 옛 이름을 남긴 별칭이다. 외부 CLI 호출은 테넌트 준수 판정(`agent-tenant-isolation-manager`), 위키 승격(`agent-wiki`), 선택적 herdr 기동 백엔드(`herdr`)뿐이다.
- 데몬은 PTY와 프로세스 그룹의 유일한 소유자다. CLI·GUI는 소켓 클라이언트일 뿐이라 둘이 죽어도 세션은 산다. 소켓은 `~/.tenants/_daemon/agent-room-terminal.sock` 하나이고 테넌트와 무관한 호스트 전역이다.
- `agent-room-monitor`는 스냅샷을 소유 CLI 출력만으로 조립한다(`CLIOwnerBridge`). 한 CLI가 실패하면 그 영역은 빈 값으로 채워지고 뿌리 노드의 `health.notes`에 한 줄이 붙으며 스냅샷 전체는 계속 만들어진다.
- `agent-room-isolator`는 git도 원장도 직접 다루지 않는다. git 워크트리는 `agent-worktree-control-terminal`, 원장 방 개설은 `agent-work-todo`에 맡기고, 확인(`trace`·`doctor`)에서만 `git worktree list --porcelain`을 읽기 전용으로 부른다.

## 대표 흐름: 방 열기 (`agent-room-terminal open <방id> --execute`)

1. CLI가 데몬을 확인하고 없으면 같은 디렉터리의 `agent-room-terminal-daemon`을 띄운다.
2. 방 입력을 읽는다. `--spec <경로>`가 있으면 그 파일, 없으면 `~/.tenants/*/rooms/`에서 방 폴더를 찾아 `spec.json`을 읽고 `events.jsonl`의 마지막 점유자·세션을 덧씌운다. 둘 다 없으면 `room-id not found`로 끝난다.
3. 프리셋(`--preset` 또는 설계도 값)과 도구(`--tool`, 없으면 허용 도구 목록에서 알아보는 첫 값, 그것도 없으면 `claude`)를 정하고, toolbelt 각 CLI를 `agent-tenant-isolation-manager check <cli> --json`으로 판정해 준수하지 않는 것은 `excludedTools`로 뺀다.
4. 방 폴더를 조립하고 `events.jsonl`에 `assembled` 사건을 붙인다.
5. 도구가 keychain으로 인증하는 경우(현재 Claude Code) keychain 값을 방 폴더의 도구 전용 config 디렉터리에 0600 파일로 복제한다.
6. 네트워크 벽이 `allow`면 데몬에 방 전용 localhost 프록시를 요청하고, `RoomOpenPolicy`가 `SeatbeltCompiler`로 seatbelt 프로필을 만든다.
7. 데몬에 `openSession`(지휘실 권한)을 보낸다. 같은 방의 살아 있는 세션이 있으면 새로 열지 않고 재사용한다. 세션 개설이 실패하면 5단계의 자격증명 사본을 지우고 오류를 낸다.
8. `events.jsonl`에 `occupied` 사건을 붙이고, 도구 전사 경로를 방에 등록하고, `ROOM.md` 본문과 함께 `{ok, result}` 봉투를 출력한다.

## 대표 흐름: 방 관측 (`agent-room-monitor snapshot`)

`SnapshotBuilder`가 `agent-work-todo placement list --all --json`, `room list --json`, `agent-seat-manager seats`, `agent-deck status`, `app-build-manager ship-queue list`, `agent-vault status`, `agent-work-monitor host`, `mac-permission-monitor status`, `agent-session-archive status`, `agent-handoff skill list`(설치 스킬), `agent-tenant-isolation-manager list`·`context current`(테넌트), `agent-session-context-ledger sessions`·`skills`(최근 7일 세션과 스킬 사용량), `agent-hooks-status`, `agent-reach-watch`를 동시에 부른다. 결과를 로비·작업실·자리·앱·스킬·세션·보관·설비 노드로 된 트리(`TwinNode`)로 묶고, 테넌트가 하나라도 있으면 테넌트 층을 한 단 더 둔다. 방의 테넌트는 `placement.tenantID`로 정하고 자리(seat)의 테넌트로 덮어쓰지 않는다. 출력 뒤 StateMirror에 요약을 게시한다.

## 외부 의존

- 시스템: `/usr/bin/sandbox-exec`, `zsh`, `/usr/bin/security`(keychain 읽기), `/usr/bin/open`, `git`, `/usr/bin/env`, `/usr/bin/pgrep`. 파티룸 빌드는 `flutter` 또는 `fvm`, 선택적으로 `gh`.
- 런타임 CLI(모두 이 저장소 밖): `agent-tenant-isolation-manager`, `agent-wiki`, `herdr`(터미널); `agent-work-todo`, `agent-worktree-control-terminal`(격리기); `agent-work-todo`, `agent-handoff`, `agent-seat-manager`, `agent-deck`, `app-build-manager`, `agent-vault`, `mac-permission-monitor`, `agent-work-monitor`, `agent-session-archive`, `agent-session-context-ledger`, `agent-hooks-status`, `agent-reach-watch`, `agent-ui-monitor`(관측판).
- 원격 패키지: swift-crypto(SandboxKit 등), swift-argument-parser, SwiftTerm 1.13.0, libghostty-spm(고정 리비전), Sparkle 2.7 이상. 첫 빌드는 네트워크가 필요하다.
