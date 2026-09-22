# 운영

## 전제

macOS 15 이상, Xcode 툴체인의 `swift`, `/usr/bin/sandbox-exec`, `zsh`. 런타임에 부르는 CLI: `agent-work-todo`, `agent-room-monitor`, `agent-tenant-isolation-manager`, `agent-wiki`(PATH). 테넌트 `tenant:gujo` 는 `agent-tenant-isolation-manager` 원장에 등록돼 있고 방 정책(허용 CLI·차단 CLI·stateRoot·wikiWorld)이 설정돼 있어야 한다.

## 빌드·테스트

```bash
cd apps/agent-room-terminal-swift
swift build                      # GUI·CLI·데몬 세 실행 파일
swift test                       # Core·데몬 테스트
swift build -c release --product agent-room-terminal-daemon
```
순서 의존: 첫 빌드는 SwiftTerm 을 받으므로 네트워크가 필요하다. 다른 패키지와 동시에 풀빌드하지 않는다(호스트 컴파일 게이트).

검사:
```bash
git ls-files 'apps/agent-room-terminal-swift' | agent-lint-catalog check --paths-from-stdin --json
agent-cli-scaffold quality --app agent-room-terminal --json
agent-room-terminal capabilities --json
```

## 데몬

```bash
agent-room-terminal daemon start          # 없으면 띄움 (open 이 자동으로도 띄운다)
agent-room-terminal daemon status --json  # running · generation
agent-room-terminal daemon stop
```
소켓 `~/.tenants/_daemon/agent-room-terminal.sock`(0600). 마지막 세션이 닫힌 뒤 유휴 초(기본 60, `tuning set idleSeconds N`)가 지나면 스스로 끝난다. LaunchAgent 로 등록하지 않는다.

## 방 세우기 — tenant:gujo 상주 방 4개

```bash
agent-tenant-isolation-manager world ensure tenant:gujo --execute --json   # tenant-gujo world + 정책 wikiWorld
agent-work-todo room add --file <설계도.json>                              # gujo-seller-operations 등 4장
agent-work-todo placement instantiate <설계도slug> --tenant tenant:gujo
agent-room-terminal open <방id> --execute                                  # 조립문 출력
agent-room-terminal tree --tenant tenant:gujo --json
```
순서 의존: world ensure 가 먼저(env `AGENT_WIKI_WORLD` 가 정책에서 나온다), 설계도 등록이 instantiate 앞, instantiate 가 open 앞.

## 방 안에서

```bash
agent-room-terminal budget <방id> --json           # ok | handoff-due | over | unknown
agent-room-terminal handoff <방id> --note "…" --execute
agent-room-terminal simulate <방id> --against <빈병id> --json
agent-room-terminal habit list|note|promote <방id> …
agent-room-terminal snapshot <방id> --lines 40
agent-room-terminal exec <방id> -- <명령>
```

## 원장 명령(이 앱이 agent-work-todo 에 보내는 것)

| 상황 | 명령 |
|---|---|
| 방 열기 | `placement occupy <plan> <room> --occupant agent:<tool>@<host> --handle <세션> --session <세션> --wall-mode full` |
| 방 닫기 | `placement tick <plan> --workdir <방>` (자리 비우기는 `placement vacate <plan> <room>` — 1.19.3, `close` 자동 배선은 다음 바퀴) |
| 핸드오프 | `placement occupy … --successor` → `placement handover <plan> <room> --state simulating|passed|failed` |
| 자식 방 | `placement spawn-room --task … --verify … --handle … --occupant … --workdir … --tenant …` |

## 환경 변수(방 env 파일이 내보내는 것)

| 키 | 뜻 |
|---|---|
| ROOM_ID · ROOM_SESSION · ROOM_TENANT · ROOM_PARENT · ROOM_PRESET | 방·세션·테넌트·부모·프리셋 |
| AGENT_TENANT | 테넌트 id |
| SWIFT_APP_STATE_ROOT | 테넌트 정책 stateRoot — 함대 앱이 상태 경로로 읽는 키 |
| AGENT_WIKI_WORLD | 테넌트 world |
| PATH | 방 bin + 기본 셸 폴더 (open 프리셋은 전체) |
| HTTP_PROXY · HTTPS_PROXY · ALL_PROXY | `closed` 는 `http://127.0.0.1:9`. `allow` 는 방 프록시 포트. `open` 은 비움 |

## 튜닝값

`agent-room-terminal tuning show|set <키> <값>`, 설정 화면과 같은 값. 키: idleSeconds 60 · ringLines 10000 · handoffFactor 0.8 · replayCount 3 · promoteSuccesses 5 · liveTerminalCap 8 · degradeMs 24.

## 설치

`app-build-manager ship apps/agent-room-terminal-swift release` — 사용자가 설치를 지시할 때만. 빌드·테스트 통과는 설치가 아니다. 설치 뒤 `agent-surface-reach matrix --slug agent-room-terminal --strict`.
