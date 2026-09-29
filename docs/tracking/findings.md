# 미해결 문제

## 세 앱이 컴파일되지 않는다

- **조건·증상**: 2026-09-30 `origin/main`(`446385f`)에서 `apps/agent-room-terminal`의 `swift build`가 데몬 타깃(`ExecRunner.swift`, `HerdrLaunchBackend.swift`, `DaemonServer+LaunchExec.swift`)에서, `apps/room-release-manager`가 CLI 타깃(`main.swift`의 `open` 분기)에서 컴파일 오류로 끝난다. `apps/agent-room-isolator/Sources/AgentRoomWorktreeCLI/main.swift`와 `apps/agent-room-terminal/Sources/AgentRoomTerminalCLI/CognitiveCommands.swift`에도 같은 꼴의 잔해가 있다. 모두 `Process()`를 `SafeProcessRunner.run(...)`으로 바꾸면서 옛 `do/catch`와 파이프 처리 줄이 남은 것이다.
- **영향**: 세 앱 모두 설치본을 새로 만들 수 없고, 테스트 기준선도 없다. 방 터미널은 방 체제의 중심이라 이 저장소 판의 벽·인가·자격증명 삭제를 런타임으로 확인할 수 없다.
- **지금 못 고치는 이유**: 소스 코드를 고쳐야 하고, 고친 뒤 세 패키지의 테스트를 처음부터 돌려 새 기준선을 잡아야 한다. 또 swift-app-mono에 같은 파일의 고친 판이 따로 있어서, 이쪽에서 독자적으로 고칠지 그쪽 판을 가져올지를 정본 결정(아래 "사본 분기" 항목)과 함께 정해야 한다.
- **접근**: swift-app-mono 판의 같은 분기(`if !safeResult.ok { … }`)를 기준으로 각 파일을 고치고, 패키지마다 `swift build`·`swift test`를 빌드 대기열로 돌린다.

## 격리기가 없는 로컬 패키지를 의존한다

- **조건·증상**: `apps/agent-room-isolator/Package.swift`가 `../../Common/System`·`../../Common/CLI`·`../../Common/UI`를 의존하는데 이 저장소에는 `Common/`이 없다. `swift build`가 패키지 해석 단계에서 끝난다.
- **영향**: 격리기는 이 저장소에서 빌드도 테스트도 할 수 없다.
- **지금 못 고치는 이유**: `CommonSystem`·`CommonCLI`·`CommonUI` 제품을 이 저장소의 킷으로 바꿀지, `Common` 패키지를 이 저장소로 옮겨 올지 결정이 필요하고, 어느 쪽이든 매니페스트와 소스를 고쳐야 한다.
- **접근**: 세 제품을 실제로 쓰는 import를 찾아 swiftkit 제품으로 바꾸고 의존을 지운다.

## swift-app-mono 사본과 갈라졌다 (사본 분기)

- **조건·증상**: 네 앱과 `swiftkit*` 킷이 swift-app-mono(`apps/<앱>`, `swiftkit*`)에도 있다. 2026-09-30 비교에서 `agent-room-terminal` 28곳, `agent-room-monitor` 34곳, `room-release-manager` 5곳, `agent-room-isolator` 4곳이 다르고, 킷 쪽은 `swiftkit/Package.swift`부터 다르다. swift-app-mono 쪽에는 이 저장소에 없는 파일(`DaemonReachability.swift`, `StreamingExecProcessRunner.swift` 등)이 있다. 이 저장소의 엔드포인트 폴백 수정(2026-09-27 커밋 셋)은 이 저장소에만 들어갔다.
- **영향**: 같은 앱을 두 곳에서 고치면 한쪽 수정이 다른 쪽에서 사라진다. 설치본이 어느 사본에서 만들어졌는지에 따라 동작이 달라진다.
- **지금 못 고치는 이유**: 어느 저장소가 이 앱들과 킷의 정본인지 저장소 주인이 정해야 한다.
- **접근**: 정본을 정한 뒤 다른 쪽을 동기화하거나 퇴역시키고, 정본이 아닌 쪽 README에 그 사실을 적는다.

## 데몬이 요청자가 선언한 지휘실 권한을 그대로 믿는다

- **조건·증상**: 데몬 요청의 `authority: "commandRoom"`은 비밀이나 서명 없이 문자열로 온다. 데몬은 이 값이 있으면 모든 op를 허용한다. `agent-room-terminal`의 `close`·`exec`·`events`·`handoff` 등은 늘 이 권한으로 요청한다. `agent-room-terminal`은 준수 판정을 통과하면 방 `bin/`에 링크된다.
- **영향**: 방 세션이 데몬 소켓에 닿을 수 있으면 `agent-room-terminal close <다른 방> --execute` 같은 명령으로 다른 방 세션을 닫거나 그 방에서 실행할 수 있다. seatbelt 규칙은 네트워크 `closed`·`allow`에서 `network*`/`network-outbound`를 막지만, `open` 네트워크 방에는 네트워크 규칙이 없다. 유닉스 소켓 연결이 이 규칙들에 실제로 막히는지는 이 저장소 판에서 실측하지 못했다.
- **지금 못 고치는 이유**: 방 터미널이 빌드되지 않아 런타임 실측을 할 수 없다. 고치려면 데몬 인가 설계(예: 지휘실 권한을 소켓 피어 PID나 방 밖 프로세스 여부로 판정)를 바꾸는 코드 변경이 필요하다.
- **접근**: 빌드를 되살린 뒤 네트워크 설정별로 방 안에서 `agent-room-terminal daemon status`와 다른 방 대상 `close`를 시도해 막히는지 확인한다. 뚫리면 `LOCAL_PEERPID`로 요청 프로세스가 방 세션 프로세스 그룹에 속하는지 보고 지휘실 권한을 거부한다.

## seatbelt가 읽기를 막지 않는다

- **조건·증상**: `SeatbeltCompiler`의 프로필은 `(allow default)`로 시작하고, 기본 프리셋 셋 모두 `denyRead`가 비어 있다. 방 세션은 홈의 모든 파일(`~/.ssh`, `~/.codex/auth.json` 등)을 읽을 수 있다.
- **영향**: 방에 앉은 에이전트가 다른 테넌트의 상태와 사용자의 자격증명 파일을 읽을 수 있다. 쓰기와 네트워크만 막힌다.
- **지금 못 고치는 이유**: 읽기 기본 차단은 에이전트 도구가 필요로 하는 읽기 경로 목록을 정해야 하는 보안 정책 결정이다. 저장소 주인이 방 격리가 읽기까지 막아야 하는지 정해야 한다.
- **접근**: 정책이 정해지면 프리셋에 `denyRead` 기본값(다른 테넌트 루트, `~/.ssh` 등)을 넣고 도구별 필요 경로를 `allowRead`로 연다.

## 앱 식별자가 서로 다르다

- **조건·증상**:
  - 격리기: PATH CLI와 번들 id는 `agent-room-isolator`인데, `capabilities`의 `name`·`cli`, `version` 출력, 상태 폴더(`.agent-room-worktree`), StateMirror 이름, `interop.json`의 `cli`, README·USAGE는 모두 `agent-room-worktree`다.
  - 파티룸: PATH CLI와 `Info.plist` 번들 id는 `room-release-manager`/`net.ranode.room-release-manager`인데, `capabilities`·`version`·`interop.json`·README·StateMirror는 `party-room-release-manager`이고, CLI `open`은 `open -b net.ranode.party-room-release-manager`로 GUI를 찾는다.
- **영향**: 상호운용 레지스트리가 `capabilities`로 읽은 이름과 PATH 이름이 달라 의존 해석이 어긋난다. 파티룸 CLI의 `open`은 설치된 번들 id와 달라 GUI를 찾지 못할 수 있다.
- **지금 못 고치는 이유**: 어느 이름을 남길지(상점 카탈로그 slug `party-room-release-manager`와 번들 id가 걸려 있다) 저장소 주인이 정해야 하고, 정한 뒤 코드·매니페스트·상점 결속을 함께 바꿔야 한다.
- **접근**: 이름을 하나로 정하고 `package-identity.json`을 정본으로 나머지를 맞춘다.

## 버전 표기가 CHANGELOG와 다르다

- **조건·증상**: `agent-room-isolator`의 `Packaging/Info.plist`는 1.0.1인데 `CHANGELOG.md` 최신 항목은 1.0.3이다. `room-release-manager`는 `Info.plist` 1.0.8, `CHANGELOG.md` 1.0.9다.
- **영향**: 설치본이 보고하는 버전과 변경 기록이 맞지 않아 낡은 설치본 판정과 업데이트 배포가 어긋날 수 있다.
- **지금 못 고치는 이유**: 어느 쪽이 실제 배포 버전인지 확인하려면 설치 기록(`app-build-manager` 원장)이 필요하고, 버전 변경은 앱 매니페스트 수정이다.
- **접근**: 배포 원장의 마지막 버전을 확인해 두 파일을 맞춘다.

## 방 터미널 앱 전용 문서가 이 저장소 코드와 다르다

- **조건·증상**: `apps/agent-room-terminal/`의 `CLAUDE.md`·`AGENTS.md`·`docs/`·`Sources/*/AGENTS.md`는 swift-app-mono 시절 내용이다. 경로를 `apps/agent-room-terminal-swift/`로 적고, 원장 쓰기가 `agent-work-todo` CLI와 `LedgerQueue`를 지난다고 적지만 이 저장소 코드에는 `LedgerQueue`가 없고 점유는 방 `events.jsonl`에 기록된다. `RoomWallKit`(없음), SwiftTerm `from: 1.15.0`(실제 `swiftkit-terminal`에서 1.13.0 고정), 튜닝 키 일곱 개(실제 다섯 개), 방 폴더 `rooms/<배치도>/<방>`(정본은 `rooms/<방id>`), GUI 터미널 SwiftTerm(실제 GUI는 Ghostty)도 코드와 다르다. `capabilities`의 `close` 설명("tick the ledger")과 `close` 출력의 고정값 `ledgerVacate: "settled"`도 실제 동작과 다르다.
- **영향**: 그 문서를 믿은 에이전트가 없는 원장 호출을 복원하거나 틀린 경로로 방을 찾는다.
- **지금 못 고치는 이유**: 그 문서가 swift-app-mono 판의 의도된 동작을 기록한 것인지, 이 저장소 판에 맞춰 고쳐야 하는 것인지는 사본 분기의 정본 결정에 달려 있다.
- **접근**: 정본이 이 저장소로 정해지면 그 문서 묶음을 이 저장소 코드 기준으로 다시 쓰고, `capabilities`의 `close` 설명과 출력 필드를 실제 동작에 맞춘다.

## README가 코드와 다르다

- **조건·증상**: 루트 `README.md`는 `room-release-manager`를 "룸 수명주기 해제 & 자원 진공 회수" 앱으로 적지만 실제로는 파티룸 Flutter 앱 배포 앱이다. 관측판 명령을 `diff`로 적지만 실제는 `compare`다. 터미널 명령을 `open --room <id>`, `close --room <id>`, `exec --launch <cmd>`로 적지만 실제는 위치 인자(`open <방id>`)이고 `--launch`는 하위 호환용 무시 플래그다. `DaemonProcessReaper`를 에이전트 좀비 회수기로 적지만 실제로는 테스트·누수된 데몬 프로세스를 `pgrep`로 찾아 끄는 도구다. 방 생성 흐름을 AWO·Gate-Spawn으로 그리지만 이 저장소 터미널 코드는 외부 원장을 부르지 않는다.
- **영향**: README만 읽은 사용자와 에이전트가 없는 명령을 쓰고, 파티룸 앱을 방 체제 부품으로 오해한다.
- **지금 못 고치는 이유**: README는 공개 저장소의 소개 문서라서 문구와 범위(파티룸 앱을 이 저장소에 계속 둘지 포함)를 저장소 주인이 정해야 한다.
- **접근**: 코드 기준으로 명령 표와 앱 설명을 고치고, 파티룸 앱을 다른 저장소로 옮길지 정한다.

## 홈 경로 직접 조립과 원시 프로세스 실행이 남아 있다

- **조건·증상**: `AgentRoomTerminalDaemon/DaemonServer+ExecProfile.swift`·`SRTSessionResolver.swift`가 `NSHomeDirectory()`를 seatbelt 프로필의 홈으로 넘긴다. `room-release-manager`의 기본 프로젝트 경로와 `agent-room-monitor`의 `mutate open-skill`이 `homeDirectoryForCurrentUser`를 쓴다. `agent-room-monitor` CLI의 `open`이 `Process()`를 직접 만든다.
- **영향**: 테넌트 문맥이나 `SWIFT_APP_STATE_ROOT`가 이 경로들에 반영되지 않는다. 호스트 lint(`hardcoded-state-root`, 원시 프로세스 금지)가 이 파일들을 바꾸는 변경을 막는다.
- **지금 못 고치는 이유**: 소스 수정이 필요하고, 데몬 쪽은 방 터미널 빌드 복구가 먼저다.
- **접근**: `StateRootKit.resolveHost`·`AppPaths`로 바꾸고, `open`은 `SafeProcessRunner`로 바꾼다.

## 방 터미널이 다른 앱의 상태 파일을 직접 읽는다

- **조건·증상**: `RoomGraphSeatChainReader`가 `agent-work-todo`가 쓰는 `~/.swift-app-state/room-graph.json`(테넌트면 테넌트 루트 아래)을 직접 읽는다.
- **영향**: 원장 앱이 파일 형식이나 위치를 바꾸면 방 트리의 좌석 사슬 표시가 조용히 빈다. 다른 앱의 상태는 CLI로만 읽는다는 규칙과 어긋난다.
- **지금 못 고치는 이유**: `agent-work-todo`에 같은 정보를 내는 CLI 명령이 있는지 확인하고, 없으면 그 앱(이 저장소 밖)에 명령을 더해야 한다.
- **접근**: `agent-work-todo`의 CLI 출력으로 바꾸고 파일 읽기를 지운다.

## toolbelt 초과 도구가 기록 없이 빠진다

- **조건·증상**: 설계도 toolbelt가 여섯 개를 넘으면 `PathPlanner`가 일곱 번째부터 링크하지 않고 `excluded`에도 넣지 않는다.
- **영향**: 방에서 도구가 사라졌는데 `open` 결과의 `excludedTools`에도, 화면의 배제 칩에도 나타나지 않는다.
- **지금 못 고치는 이유**: 초과를 조립 실패로 할지, 배제 목록에 남길지 정책을 정해야 하고, RoomKit(공용 킷) 수정이라 사본 분기 결정의 영향을 받는다.
- **접근**: 초과 도구를 `excluded`에 사유와 함께 넣는다.

## 격리기 `--no-spawn`이 원장에 없는 방 id를 만든다

- **조건·증상**: `provision --no-spawn`은 방 id와 배치 id를 새 UUID로 만든다. CHANGELOG 1.0.0은 "원장 응답에 id가 없으면 오류(없는 id를 지어내지 않음)"라고 적는다. 이렇게 만든 결속은 원장이 한 건이라도 있으면 `list`·`doctor`에 나오지 않는다.
- **영향**: 원장에 없는 방 폴더가 생기고, 목록에서 보이지 않아 정리되지 않는다.
- **지금 못 고치는 이유**: `--no-spawn`을 없앨지, 원장 없는 결속을 목록에 합칠지 앱 주인의 결정이 필요하다.
- **접근**: `list`가 원장 결과와 로컬 결속을 합치게 하거나, `--no-spawn`을 원장 없는 시험용으로 표시한다.

## 공용 킷에 퇴역한 호스트와 사설 주소가 남아 있다

- **조건·증상**: `swiftkit/Sources/DBViewerKit/Models.swift`의 기본 연결 이름이 `k3s-prod via pve`이고 점프 호스트 기본값이 사설 IP다. `swiftkit/Tests`의 여러 픽스처(`AgentContextKitTests`, `AgentSessionKitTests`, `CredentialLifecycleKitTests`)가 옛 사내 GitLab 호스트 이름을 쓴다. Linux 호스트 pve와 옛 사내 GitLab 호스트는 2026-09-24 퇴역했다. 또 `swiftkit-terminal`·`swiftkit-sparkle`·`swiftkit-appscaffold` 매니페스트 주석은 swiftkit이 "외부 의존성 0건"이라고 적지만 `swiftkit/Package.swift`는 swift-crypto와 swift-argument-parser를 의존한다.
- **영향**: DBViewerKit을 쓰는 앱의 기본 연결이 없는 호스트를 향한다. 공개 저장소에 사내 주소가 노출돼 있다. 주석을 믿고 swiftkit 의존 그래프를 판단하면 틀린다.
- **지금 못 고치는 이유**: 이 킷들은 방 체제와 무관하고 swift-app-mono 사본과 함께 고쳐야 하므로 사본 분기의 정본 결정이 먼저다. 기본값을 무엇으로 바꿀지도 DBViewerKit 사용 앱 쪽 결정이 필요하다.
- **접근**: 정본 킷에서 기본값을 비우거나 설정 필수로 바꾸고, 픽스처는 `example.invalid` 같은 예약 도메인으로 바꾼다. 매니페스트 주석은 실제 의존에 맞춘다.
