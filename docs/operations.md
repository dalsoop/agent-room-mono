# 운영

## 전제

- macOS 15 이상(모든 패키지의 `platforms`가 `.macOS(.v15)`), Swift 6.1 이상 툴체인(매니페스트 `swift-tools-version: 6.1`, 트레잇 사용).
- 첫 빌드용 네트워크(GitHub에서 SwiftTerm·libghostty-spm·Sparkle·swift-crypto·swift-argument-parser를 받는다).
- 방 터미널 실행용: `/usr/bin/sandbox-exec`, `zsh`, 그리고 테넌트 준수 판정을 위한 `agent-tenant-isolation-manager`(PATH). 없으면 toolbelt 판정이 실패해 도구가 배제된다.
- 격리기 실행용: `agent-work-todo`, `agent-worktree-control-terminal`(PATH), `git`.
- 관측판 실행용: 스냅샷 공급 CLI(`agent-work-todo`, `agent-seat-manager`, `agent-deck`, `app-build-manager`, `agent-vault`, `mac-permission-monitor`, `agent-work-monitor`, `agent-session-archive`, `agent-handoff`, `agent-session-context-ledger`, `agent-tenant-isolation-manager`, `agent-hooks-status`, `agent-reach-watch`)와 AX 조회용 `agent-ui-monitor`. 없는 CLI는 스냅샷에서 빈 영역으로 남을 뿐 명령은 실패하지 않는다.
- 파티룸 빌드용: `flutter` 또는 `fvm`, 대상 프로젝트(`flutter-app-mono`의 `game-party-room-app`), 선택적으로 `gh`.
- 서브에이전트 세션에서는 `build-queue-manager`(PATH)가 필요하다.

## 저장소 받기

```bash
git clone https://github.com/dalsoop/agent-room-mono.git
cd agent-room-mono
# 동시 작업은 워크트리로 나눈다(같은 체크아웃에 여러 세션이 붙을 수 있다)
git worktree add ../agent-room-mono-<작업> -b <브랜치> origin/main
```

## 빌드와 테스트

패키지마다 따로 돈다. 킷을 먼저 빌드할 필요는 없다(앱 빌드가 상대 경로 킷을 함께 빌드한다). 같은 차례에 두 패키지를 동시에 풀빌드하지 않는다.

```bash
# 사람 셸에서
cd apps/agent-room-monitor && swift build && swift test

# 서브에이전트 세션에서(직접 swift 실행이 훅에 막힌다)
build-queue-manager submit 'swift build' --workdir "$PWD/apps/agent-room-monitor" --wait
build-queue-manager submit 'swift test'  --workdir "$PWD/apps/agent-room-monitor" --wait
```

| 패키지 | 명령 | 2026-09-30 상태 |
|---|---|---|
| `apps/agent-room-terminal` | `swift build`, `swift test` | 데몬 타깃 컴파일 실패(기존 결함) |
| `apps/agent-room-monitor` | `swift build`, `swift test` | 통과 |
| `apps/agent-room-isolator` | `swift build`, `swift test` | 패키지 해석 실패(`../../Common/*` 없음) |
| `apps/room-release-manager` | `swift build`, `swift test` | CLI 타깃 컴파일 실패(기존 결함) |
| `swiftkit-terminal` | `swift test` | 통과 |
| `swiftkit-appscaffold` | `swift test` | 통과 |
| `swiftkit-sparkle` | `swift test` | 통과 |
| `swiftkit` | `swift test --filter <킷>Tests` | 전체 테스트는 244개 킷을 모두 빌드하므로 오래 걸린다. 바꾼 킷의 테스트만 필터로 돌린다 |

`swiftkit/scripts/game-realtime-checked-swift-test`는 게임 실시간 킷용 셸 도우미이고 방 체제와 무관하다.

`Project.swift`와 `Derived/`는 Tuist 매니페스트와 그 생성물이다. SwiftPM 빌드에는 쓰이지 않는다.

## 설치

설치는 이 저장소 밖의 `app-build-manager`가 맡는다. 빌드·테스트 통과는 설치가 아니다. 설치된 앱은 `/Applications/<GUI 이름>.app`이고, PATH CLI는 번들의 `Contents/Helpers/<cli>`를 가리키는 심링크다. 설치 뒤 확인은 `<cli> version`과 `<cli> capabilities`다. 설치본이 소스보다 낡으면 CLI가 stderr에 경고를 낸다.

## 방 터미널 데몬

```bash
agent-room-terminal daemon start           # 없으면 띄운다(open --execute도 자동으로 띄운다)
agent-room-terminal daemon status --json   # running · generation · socket
agent-room-terminal daemon stop
agent-room-terminal doctor                  # 런타임 점검, 남은 데몬 소켓 정리
```

- 데몬 실행 파일은 CLI와 같은 디렉터리의 `agent-room-terminal-daemon`에서 찾는다.
- 호스트 전역 파일(테넌트와 무관): 소켓 `~/.tenants/_daemon/agent-room-terminal.sock`, 세대 번호 `~/.tenants/_daemon/agent-room-terminal.generation`, 로그 `~/.tenants/_daemon/agent-room-terminal.log`. `SWIFT_APP_STATE_ROOT`가 있으면 `~` 대신 그 루트 아래다.
- 마지막 세션이 닫히고 유휴 시간(기본 60초)이 지나면 데몬이 스스로 끝난다. 세대 번호가 바뀌었으면 그전 세션은 모두 사라진 것이다.
- LaunchAgent로 상주시키지 않는다.

튜닝값은 `agent-room-terminal tuning show|set <키> <값>`으로 바꾼다. 키와 기본값: `idleSeconds` 60, `ringLines` 10000, `handoffFactor` 0.8, `replayCount` 3, `promoteSuccesses` 5.

## 방 하나 열고 닫기

```bash
agent-room-terminal open <방id> --json                 # 계획만(부수효과 없음)
agent-room-terminal open <방id> --execute --json       # 조립 → 세션 → ROOM.md 출력
agent-room-terminal snapshot <방id> --lines 40
agent-room-terminal exec <방id> -- ls bin
agent-room-terminal close <방id> --execute
```

순서 의존: 방 폴더에 `spec.json`이 먼저 있어야 한다(격리기 `provision`이나 원장 방 생성이 만든다). `--spec <파일>`로 직접 줄 수도 있다.

## 방과 워크트리 결속

```bash
agent-room-isolator provision --task "…" --verify "swift test" --repo <저장소> \
  --occupant agent:claude@<호스트> --tenant tenant:<슬러그> --dry-run --json
agent-room-isolator provision …(같은 인자, --dry-run 없이)
agent-room-isolator trace --room <방id> --json
agent-room-isolator doctor --json
```

순서 의존: `agent-worktree-control-terminal create`가 성공해야 `agent-work-todo spawn-room`을 부른다. `--occupant`가 없으면 환경 변수 `FORGE_ACTOR`, 그다음 `AGENT_ACTOR`를 쓰고, 그것도 없으면 exit 64다.

## 환경 변수

| 키 | 누가 읽나 | 뜻 |
|---|---|---|
| `SWIFT_APP_STATE_ROOT` | 모든 앱 | 상태 루트 강제. 있으면 앱 상태가 `<루트>/.<slug>/`로 모이고 고객용 저장소를 쓰지 않는다. 테스트와 방 env에서 쓴다 |
| `ROOM_TENANT` · `AGENT_TENANT` · `TENANT_ID` | StateRootKit | 이 순서로 테넌트를 정한다. 정해지면 상태 루트가 `~/.tenants/<슬러그>` |
| `SWIFT_APP_FAIL_CLOSED_STALE=1` | 모든 CLI | 설치본이 낡았으면 exit 70으로 멈춘다 |
| `SWIFT_APP_NO_STALE_BANNER` | 모든 CLI | 낡은 설치본 경고를 끈다 |

방 `env` 파일이 방 세션에 내보내는 키: `ROOM_ID`, `ROOM_SESSION`, `ROOM_TENANT`, `ROOM_PARENT`, `ROOM_PRESET`, `AGENT_TENANT`, `TENANT_ID`, `SWIFT_APP_STATE_ROOT`(방 테넌트의 상태 루트), `AGENT_WIKI_WORLD`(테넌트 위키 world), `PATH`(방 `bin/` + 기본 셸 폴더, open은 호스트 PATH), `HTTP_PROXY`·`HTTPS_PROXY`·`ALL_PROXY`, `CLAUDE_CONFIG_DIR`(keychain 사본을 쓰는 도구만), `HOME`, `USER`, `LANG`, `PWD`, `GIT_CONFIG_COUNT` 계열.

## 상태 파일 위치

| 앱 | 상태 디렉터리(`SWIFT_APP_STATE_ROOT` 없음) | 주요 파일 |
|---|---|---|
| agent-room-terminal | `~/Library/Application Support/net.ranode.shared/rooms/room-default/agent-room-terminal/`, 방은 `~/.tenants/<테넌트>/rooms/<방id>/` | 튜닝 `tuning.json`, 방 `spec.json`·`events.jsonl`·`env`·`bin/`·`state/` |
| agent-room-monitor | `~/Library/Application Support/net.ranode.shared/rooms/room-default/agent-room-monitor/` | `trace/`, `snapshots/`, `views/*.json` |
| agent-room-isolator | `~/Library/Application Support/net.ranode.shared/rooms/room-default/agent-room-worktree/` | `binds.json` |
| room-release-manager | StateRootKit 루트 아래 `.party-room-release-manager/` | `config.json` |

StateMirror 요약은 앱마다 `~/.swift-app-state/<이름>.json`이다(격리기는 `agent-room-worktree.json`, 파티룸은 `party-room-release-manager.json`). 정본이 아니라 관측용이다.
