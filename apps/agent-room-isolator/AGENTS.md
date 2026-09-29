# agent-room-isolator

방 개념(task·verify)을 먼저 검증하고, git 워크트리를 만들어 그 방에 결속한 뒤, 방 폴더에 `ROOM.md`·`DESIGN.md`·`AGENTS.md`를 발행하는 macOS 창 앱이다. PATH CLI와 번들 id는 `agent-room-isolator`지만 코드 안의 앱 이름·상태 slug·`capabilities` 이름은 `agent-room-worktree`이고, 타깃 이름도 `AgentRoomWorktree*`다.

## 범위

- `AgentRoomWorktreeCore`: 방 개념 검증과 slug(`RoomConcept`), 결속 모델(`Models`), 결속 저장(`BindStore` → `binds.json`), 방 문서 틀(`RoomBirthDocuments`), 방 `spec.json`으로 결속 보강(`RoomSpecEnrichment`), 원장·git 출력 파싱(`RoomTraceParse`), 서비스(`AgentRoomWorktreeService`: provision·bind·emitMd·list·show·trace·doctor), 경로(`RoomWorktreePaths`), StateMirror 게시.
- `AgentRoomWorktree`(GUI): 방 사이드바, 빈 방 칸, 방 상세(개념·워크트리·원장·문서 절), provision 시트.
- `AgentRoomWorktreeCLI`: 명령 분기, `--json` 봉투, 오류 메시지 현지화.

## 범위 밖

- git 워크트리 생성·삭제: `agent-worktree-control-terminal create … --inside`에 맡긴다. `git worktree add`를 직접 부르지 않는다. 읽기(`git -C <repo> worktree list --porcelain`)만 한다.
- 방 원장: `agent-work-todo spawn-room`·`placement list`·`placement show`로만 다룬다. 원장 파일을 직접 읽거나 쓰지 않는다.
- 저장소 루트의 `AGENTS.md`: 방 폴더에 쓰는 `AGENTS.md`는 방 폴더 안 파일이고, 작업 대상 저장소의 루트 문서를 건드리지 않는다.
- 세션·벽·PTY(방 터미널 앱의 일).

## 불변식

- `task`가 공백뿐이면 `taskEmpty`, `verify`가 비었거나 `true`·`:`·`exit 0`·`echo ok`(대소문자 무시)면 `trivialVerify`로 거부한다. 이 검증은 워크트리 생성보다 먼저 돈다.
- slug는 ASCII 영문자·숫자만 남기고 나머지를 `-` 하나로 접어 48자까지 쓴다. 두 글자 미만이면 대체값(`room`)이다.
- 워크트리 경로는 `<repo>/.worktrees/<slug>`, 기준은 `origin/main`이다.
- 원장 방 개설은 워크트리 생성이 성공한 뒤에만 한다. `spawn-room` JSON에 `roomID`·`planID`가 없으면 `spawnRoomFailed`로 멈추고 결속을 만들지 않는다.
- `--dry-run`은 러너를 한 번도 부르지 않는다(테스트 `testDryRunDoesNotCallRunner`).
- 결속은 `binds.json`과 방 폴더 `bind.json` 두 곳에 같은 내용으로 쓴다. `trace`의 `markerOK`는 `bind.json`의 방 id·배치 id·워크트리 경로가 결속과 같을 때만 참이다.
- 방 폴더의 `worktree` 심링크는 없을 때만 만든다. 있으면 덮어쓰지 않는다.
- `--occupant`가 없으면 `FORGE_ACTOR`, 그다음 `AGENT_ACTOR` 환경 변수를 쓴다. 셋 다 없거나 `--tenant`가 없으면 exit 64다.
- GUI가 시작할 때 헬스 펄스 `~/.swift-app-state/pulse/agent-room-worktree.pulse`를 쓴다.
- 상태 경로는 `RoomWorktreePaths`(StateRootKit)에서만 나온다. `SWIFT_APP_STATE_ROOT`가 없으면 앱 상태는 `~/Library/Application Support/net.ranode.shared/rooms/room-default/agent-room-worktree/`, sqlite는 StateRootKit 루트 아래 `Library/Application Support/net.ranode.agent-room-worktree/app.sqlite`, 방 폴더는 테넌트 상태 루트의 `rooms/<방id>`다.

## 구현 패턴

- 외부 명령은 모두 `CommandRunning` 주입으로 `/usr/bin/env <cli> …` 꼴로 부른다. 테스트는 가짜 러너로 argv를 기록한다.
- 파일 조작은 `RoomFiles`를 거친다(`FileManager.default` 직접 사용 대신).
- 오류는 `AgentRoomWorktreeError`로 던지고, CLI의 `failureMessage`가 현지화 문자열로 바꾼다. 새 오류 case를 더하면 그 switch와 문자열 키를 함께 더한다.
- CLI에 명령을 더하면 `capabilities`의 `commands`, 사용법 예시, GUI 표면(사이드바·상세·시트)을 함께 더한다.
- 새 외부 CLI 의존은 `capabilities`의 `depends`와 `interop-expects.json`에 같은 명령과 이유로 적는다.

## 알려진 상태 (2026-09-30)

- `Package.swift`가 이 저장소에 없는 `../../Common/{System,CLI,UI}`를 의존해 패키지 해석이 실패한다.
- CLI `main.swift`의 `open` 분기에 `SafeProcessRunner` 치환 잔해(짝 없는 `} catch {`)가 있다.
- `Info.plist` 버전(1.0.1)이 `CHANGELOG.md`(1.0.3)보다 낮다.

## 테스트

- `Tests/AgentRoomWorktreeCoreTests/SmokeTests.swift`(XCTest 14개): 형식 계약, 개념 검증, slug, 점유자 환경 변수, 문서 틀 치환, dry-run 무호출, provision이 결속과 문서를 쓰는지, id 없는 spawn JSON 실패, trace가 원장과 git을 잇는지, 원장 목록 파싱.
- 테스트는 `SWIFT_APP_STATE_ROOT`를 임시 폴더로 준 격리 환경(`isolatedEnv()`)을 쓴다. 실제 `~/.tenants`에 방 폴더를 만들면 결함이다.
- 새 경로에서 확인할 것: 원장이 비었을 때 `binds.json`으로 돌아가는지, `spec.json` 값이 결속을 덮어쓰는 순서(`workdir`·`verdict`는 덮고 `task`는 빈 때만), `--no-spawn` 결속이 원장이 있을 때 목록에서 빠지는 현재 동작.
