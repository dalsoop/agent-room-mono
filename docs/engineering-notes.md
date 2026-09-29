# 함정과 메커니즘

## 빌드

- **증상**: `swift build`가 `error: expected declaration`, `extraneous '}' at top level`, `static methods may only be declared on a type`로 한 파일에서 수십 개씩 실패한다. **원인**: `Process()`를 `SafeProcessRunner.run(...)`으로 기계적으로 바꾸면서 옛 `do { try p.run() } catch { … }`의 `} catch {` 부분과 파이프 처리 줄이 남았다. `SafeProcessRunner.run`은 던지지 않고 결과(`ok`·`exitCode`·`stdout`·`stderr`·`trimmedStderr`)를 돌려준다. **대응**: 남은 `catch` 블록을 지우고 `if !safeResult.ok { … }`로 결과를 검사한다. 인자 목록에 `workingDirectory:` 같은 이름 붙은 인자를 끼울 때는 앞 인자 뒤의 쉼표를 확인한다. **검증**: 해당 패키지 `swift build`가 0으로 끝나는지, `git grep -n 'let safeResult' -- apps` 결과마다 바로 아래에 `} catch {`가 없는지 본다.
- **증상**: `agent-room-isolator`에서 `swift build`가 컴파일 전에 `the package at '…/Common/System' cannot be accessed`로 끝난다. **원인**: 매니페스트가 `../../Common/System`·`CLI`·`UI`를 의존하는데 이 저장소에는 `Common/`이 없다(swift-app-mono 구조의 흔적). **대응**: 그 세 패키지가 주던 제품(`CommonSystem`·`CommonCLI`·`CommonUI`)을 쓰는 코드를 찾아 이 저장소의 킷으로 바꾸거나 의존을 지운다. **검증**: `swift package describe`가 오류 없이 끝나는지 본다.
- **증상**: 서브에이전트에서 `swift build`·`swift test`가 훅에 막힌다. **대응**: `build-queue-manager submit '<명령>' --workdir <패키지> --wait`로 돌리고, 출력은 파일로 받는다.
- 첫 빌드는 원격 패키지(SwiftTerm, libghostty-spm, Sparkle, swift-crypto, swift-argument-parser)를 받느라 네트워크가 필요하고 오래 걸린다. 워크트리마다 `.build`가 따로 생기므로 워크트리를 나누면 각자 다시 받는다.
- 커밋된 `Package.resolved` 일부(`room-release-manager`, `swiftkit-appscaffold`, `swiftkit-sparkle`)는 현재 매니페스트와 맞지 않아(예: `swift-argument-parser` 핀 없음) 빌드하면 다시 쓰인다(2026-09-30 확인). 의존을 바꾸지 않는 작업에서는 빌드 뒤 `git status`로 이 변경을 확인하고 되돌린다. 의존을 바꾸는 작업에서는 다시 쓰인 파일을 함께 커밋한다.

## 트레잇

- **증상**: 앱에서 Telemetry(크래시 수집)가 켜지지 않는다. **원인**: SwiftPM 규칙상 소비자가 `.package(path:, traits: [...])`를 적으면 제공자의 기본 트레잇이 꺼지고 적은 것만 켜진다. `agent-room-terminal`·`agent-room-monitor`·`agent-room-isolator`는 `["GujoManaged", "SelfUpdating"]`만 적어서 Telemetry가 꺼져 있고, `room-release-manager`는 셋 다 적었다. **대응**: 트레잇을 바꿀 때는 원하는 전체 집합을 적는다. 트레잇이 꺼지면 해당 모듈은 빌드되지 않고 심볼도 없다.
- `GujoManaged.exitIfNotEntitledSync()`는 2026-09-21 라이선스 게이트 퇴역 뒤로 막지 않는다. 지금 하는 일은 설치본이 소스보다 낡았으면 stderr에 경고 한 줄을 내는 것뿐이다. `SWIFT_APP_FAIL_CLOSED_STALE=1`이면 낡은 설치본에서 exit 70으로 멈추고, `SWIFT_APP_NO_STALE_BANNER`가 있으면 경고를 끈다. `--json`이 있으면 강제 모드가 아닌 한 경고를 내지 않는다.

## 저장 경로가 두 갈래다

- **증상**: 터미널·관측판·격리기의 상태 파일(`tuning.json`, `trace/`, `snapshots/`, `views/`, `binds.json`)이 `~/.agent-room-terminal/`·`~/.agent-room-monitor/`·`~/.agent-room-worktree/`에 없다. **원인**: `SWIFT_APP_STATE_ROOT`가 없으면 앱 상태 디렉터리가 `StateRootKit.ensureCustomerRoomStorage(slug:)`, 즉 `~/Library/Application Support/net.ranode.shared/rooms/room-default/<slug>/`로 간다. 반면 sqlite는 `StateRootKit` 루트(홈 또는 `~/.tenants/<슬러그>`) 아래 `Library/Application Support/net.ranode.<slug>/app.sqlite`이고, 방 폴더는 `~/.tenants/<테넌트>/rooms/`다. **대응**: 경로를 추측하지 말고 `<cli> capabilities`의 `state` 항목을 읽는다. 테스트에서는 `SWIFT_APP_STATE_ROOT`를 주면 모든 상태가 그 아래 `.<slug>/`로 모인다.
- 격리기의 slug는 `agent-room-worktree`다(CLI 이름 `agent-room-isolator`와 다르다). 상태 폴더 이름·StateMirror 파일·sqlite 번들 이름이 모두 `agent-room-worktree`를 쓴다.

## 방 폴더 찾기

- 정본 경로는 `~/.tenants/<테넌트>/rooms/<방id>`다. 찾을 때(`RoomPaths.findRoomDirectory`)는 정본을 먼저 보고, 없으면 `rooms/` 바로 아래에서 이름이 같은 폴더, 그다음 옛 2단 경로(`rooms/<배치도>/<방>`)에서 폴더 이름이나 폴더 안에 선언된 방 id가 대소문자 무시로 같은 것을 찾는다. 테넌트를 주지 않으면 `_base-bin`을 뺀 모든 테넌트 폴더를 차례로 뒤진다.
- 방 id는 NFC(`precomposedStringWithCanonicalMapping`)로 맞춘 뒤 비교한다. 한글 handle을 NFD로 만든 폴더는 정규화 없이 비교하면 못 찾는다.
- 격리기는 방 폴더를 `RoomWorktreePaths.roomDirectory`(`<테넌트 루트>/rooms/<방id>`)로 만든다. 터미널은 방 폴더를 찾지 못하면 같은 규칙의 정본 경로를 새로 만든다.

## 터미널 엔진

- **증상**: GUI 터미널 칸이 비어 있고 오류도 없다. **원인**: `TerminalEngineFactory.make`는 요청한 엔진 종류가 등록되지 않았으면 `MockTerminalEngine`을 조용히 돌려준다. 기본 종류는 `ghostty`이고 등록은 앱이 시작할 때 `register(_:creator:)`로 한다. **대응**: 엔진을 만들기 전에 `TerminalEngineFactory.isRegistered(.ghostty)`를 확인한다.
- SwiftTerm은 `swiftkit-terminal`에서 1.13.0으로 정확히 고정돼 있다. 앱 패키지에서 SwiftTerm을 따로 끌어오지 않는다.

## 벽과 bin

- toolbelt가 여섯 개를 넘으면 뒤쪽 도구는 링크되지 않고 `excludedTools`에도 남지 않는다. "도구가 방에 없다"는 보고가 오면 먼저 설계도 toolbelt 순서와 개수를 본다.
- 방 설정의 상대 쓰기 경로는 작업 디렉터리(`workdir`, 보통 git 워크트리) 기준으로 펼친다. `workdir`가 없으면 방 폴더 기준이다. 방 폴더 기준으로 펼치면 워크트리 쓰기가 전부 막힌다(실측 2026-09-05).
- git 워크트리에서 커밋하려면 워크트리의 `.git` 파일이 가리키는 공용 git 디렉터리에도 쓰기가 필요하다. `SeatbeltCompiler`가 `workdir`의 `.git` 파일을 읽어 그 경로를 쓰기 허용에 더한다.
- seatbelt 프로필은 기본 허용이다. 읽기 차단은 `denyRead`를 명시했을 때만 생긴다.

## 자격증명

- **증상**: 방 안에서 Claude Code가 `/login`에 계속 실패한다. **원인**: seatbelt가 keychain IPC를 막는다(실측 2026-09-04). **대응**: `open`이 keychain 값을 방 `state/claude-config/.credentials.json`에 복제하고 `CLAUDE_CONFIG_DIR`를 그쪽으로 돌린다. `open` 결과의 `credentialSeed`가 `failed`면 이 Mac의 keychain에 `Claude Code-credentials` 항목이 없거나 읽기가 거부된 것이다.
- 사본을 지울 때 config 폴더를 통째로 지우면 같은 폴더의 도구 전사(`projects/`)가 사라져 사용량 측정이 끊긴다(실측 2026-09-04). 자격증명 파일 하나만 지운다.

## 관측판

- **증상**: 관측판이 비었거나 일부 영역만 0이다. **원인**: 스냅샷은 소유 CLI 열세 개를 병렬로 부르고, 실패한 CLI는 빈 값과 `root.health.notes`의 한 줄로 대신한다. 전체 명령은 성공으로 끝난다. **대응**: `agent-room-monitor snapshot --json`의 `root.health.notes`를 먼저 읽는다.
- 다른 앱 CLI의 stdout 앞뒤에 경고 배너가 붙을 수 있다. 관측판은 `CLIJSON`으로 첫 `{`(또는 `[`)부터 마지막 `}`(또는 `]`)까지 잘라 파싱한다. 새 브리지를 만들 때도 같은 함수를 쓴다.
- `Sources/AgentRoomMonitor/HexBoard.swift`는 `Package.swift`에서 `exclude`돼 빌드에 들어가지 않는다. 이 파일을 고쳐도 앱은 바뀌지 않는다.

## 격리기

- `list`는 원장(`agent-work-todo placement list --json`)이 한 건이라도 돌려주면 로컬 `binds.json`을 보지 않는다. `--no-spawn`으로 만든 결속은 원장에 없어서 이때 `list`·`doctor`에 나오지 않는다. `show --room <id>`는 로컬 결속으로 돌아가므로 여전히 찾는다.
- 한글만 있는 `task`는 slug가 `room`이 된다. 같은 저장소에서 두 번째 방을 만들면 워크트리 이름이 겹친다. 한글 task에는 `--name`을 준다.

## 벽이 서는지 확인하는 순서

방을 연 뒤 방 터미널에서 차례로 확인한다.

1. `echo $PATH` → 방 `bin/`과 기본 셸 폴더뿐인지.
2. `which kubectl` → 찾지 못하는지.
3. `/usr/bin/whoami` → `restricted`로 거부되는지.
4. `echo x > ../outside.txt` → 리다이렉션이 거부되고 방 밖에 파일이 생기지 않았는지.
5. 방 설정 네트워크가 `closed`면 `git ls-remote https://github.com/dalsoop/agent-room-mono` → 실패하는지.
6. 방을 닫은 뒤 `state/claude-config/.credentials.json`이 없는지.
