# 규칙

## 패키지 경계

- 빌드 단위는 `apps/*`의 앱 패키지 넷과 킷 패키지 넷이다. 저장소 루트에 `Package.swift`를 두지 않는다.
- 앱 패키지는 킷을 `.package(path: "../../<킷>")`로만 끌어온다. 킷 패키지끼리는 `../<킷>`이다.
- 앱은 다른 앱의 타깃을 import하지 않는다. 앱 사이의 연동은 PATH CLI 호출뿐이다.
- 킷 의존 방향은 `swiftkit-appscaffold → swiftkit-sparkle → swiftkit`, `swiftkit-terminal → swiftkit`으로 고정한다. `swiftkit`이 다른 킷 패키지를 의존하면 순환이 생긴다(`cyclic dependency declaration found`).
- `swiftkit`에 새 원격 패키지 의존을 더하지 않는다. 무거운 외부 의존(터미널 엔진, Sparkle)은 별도 킷 패키지로 분리한다. 이미 있는 swift-crypto·swift-argument-parser는 예외로 남아 있다.

## 타깃 링크

- PATH CLI 타깃(`AgentRoomTerminalCLI`, `AgentRoomMonitorCLI`, `AgentRoomWorktreeCLI`, `PartyRoomReleaseManagerCLI`)의 소스는 AppKit·SwiftUI를 import하지 않는다. 의존 목록에는 AppKit·SwiftUI를 쓰는 킷(`*UIKit`, `SettingsUIKit`, `OnboardingUIKit`, `WindowChromeKit` 등)과 `TerminalEngineSwiftTerm`·`TerminalEngineGhostty`를 의존 목록에 넣지 않는다. 위반은 CLI 소스의 import와 `Package.swift`의 CLI 타깃 직접 의존 목록으로 판정한다. 예외로 모든 CLI가 `AppScaffoldKit`을 의존하는데, 이 킷에는 SwiftUI를 import하는 파일이 있어 SwiftUI가 간접으로 링크된다. CLI 진입점에서 그 SwiftUI 타입을 부르지 않는다.
- Core 라이브러리 타깃은 AppKit·SwiftUI·SwiftTerm을 import하지 않는다.
- 터미널 엔진은 `agent-room-terminal`의 데몬 타깃(`TerminalEngineSwiftTerm`)과 GUI 타깃(`TerminalEngineGhostty`)에만 링크한다.
- GUI 실행 파일을 PATH에 심링크하지 않는다. PATH에 올라가는 것은 앱 번들의 `Contents/Helpers/<cli>`뿐이다(`package-identity.json`의 `cli_helper_path`).

## 프로세스 실행

- Core 타깃에서 `Process()`·`system()`·`posix_spawn()`을 직접 쓰지 않는다. `CommandKit`의 `ProcessCommandRunner`·`SafeProcessRunner`·`CommandKitSync`·`ShellCommand`를 쓴다(64KB 파이프 교착을 막는다).
- 알려진 예외는 둘이다: 데몬의 PTY 생성(SwiftTerm), CLI의 데몬 기동(`DaemonCommand`의 `posix_spawn`, 표준 출력·오류를 데몬 로그 파일로 돌린다). 새 예외를 만들지 않는다.
- 외부 CLI 호출은 Core에서 프로토콜(`CommandRunning`, `OwnerFetching`, `ComplianceChecking` 등) 뒤에 두고, 테스트는 가짜 구현을 주입한다. 테스트가 실제 원장·실제 `~/.tenants`·실제 keychain을 건드리면 결함이다.

## 상태 경로

- 모든 상태 경로는 `StateRootKit`과 앱별 `AppPaths`(`RoomWorktreePaths` 포함)에서 나온다. 새 코드에서 `NSHomeDirectory()`·`FileManager.default.homeDirectoryForCurrentUser`·`expandingTildeInPath`로 홈을 조립하면 위반이다(호스트 lint 규칙 `hardcoded-state-root`).
- 테스트는 `SWIFT_APP_STATE_ROOT`를 임시 폴더로 주거나, 테스트 러너 감지로 `$TMPDIR/swift-app-state-root-tests`를 쓴다.
- 방 폴더는 `RoomPaths.roomDirectory(tenant:roomID:)`(`~/.tenants/<테넌트>/rooms/<방id>`)로 만들고, 찾을 때는 `RoomPaths.findRoomDirectory`를 쓴다. 방 폴더 경로를 문자열로 이어 붙이지 않는다.

## CLI 계약

- 모든 CLI는 `capabilities`를 가진다. `capabilities`는 InteropKit 봉투(`{"ok": true, "result": {...}}`)로 `name`·`cli`·`commands`·`state`·`health`·`depends`를 낸다. `commands` 배열과 실제 서브커맨드 분기표는 같아야 한다. 하나만 바꾸면 계약 위반이다.
- `capabilities`의 `depends`에 적은 CLI는 `interop-expects.json`에도 같은 명령과 이유로 적는다(격리기·터미널).
- `help`·`version`·`capabilities`는 어떤 게이트에도 막히지 않는다.
- 사용법 오류는 exit 64, 일반 실패는 exit 1이다. `agent-room-terminal check`의 차단만 exit 2다.
- `agent-room-terminal`의 부작용 명령(`open`·`close`·`handoff`·`habit promote` 등)은 `--execute` 없이는 계획만 출력하고 부수효과가 없다.

## 버전과 변경 기록

- 동작이 바뀌는 앱 변경은 그 앱의 `Packaging/Info.plist` `CFBundleShortVersionString`을 올리고 `CHANGELOG.md`에 같은 번호로 항목을 더한다(호스트 lint 규칙 `marketing-version-bump`).
- 커밋 메시지는 영어 `type(scope): subject` 꼴이다(예: `fix(endpoint-router-kit): …`, `chore(apps): …`).
- 한 커밋은 앱 하나 또는 킷 하나의 변경을 담는다. 킷 변경과 그 킷을 쓰는 앱 변경은 커밋을 나눈다.
- 스테이징은 경로를 명시해서 한다. `git add -A`·`git commit -a`를 쓰지 않는다.

## 트레잇

- `swiftkit-appscaffold`의 기본 트레잇은 `GujoManaged`·`SelfUpdating`·`Telemetry` 셋이다. 앱이 `traits:`를 적으면 기본값이 꺼지고 적은 것만 켜진다. 기본과 다른 조합을 적는 앱은 매니페스트에 그 이유를 주석으로 남긴다.

## 문안

- GUI 문안과 사람이 읽는 CLI 출력은 LocalizationKit 키(`L10n`, `CLILocalization`)로 낸다. 기계가 읽는 `capabilities`의 `summary`는 영어 고정이 원칙이다.

## 검증 게이트 (병합 전)

바꾼 패키지마다 아래를 이 Mac에서 돌리고 종료 코드 0을 확인한다. 서브에이전트 세션은 호스트 훅 때문에 `swift build`·`swift test`를 직접 돌릴 수 없고 빌드 대기열을 거친다.

```bash
build-queue-manager submit 'swift build' --workdir <패키지 경로> --wait
build-queue-manager submit 'swift test'  --workdir <패키지 경로> --wait
```

- 출력은 파일로 남기고 `head`·`tail`·`grep` 파이프로 자르지 않는다.
- 같은 차례에 두 패키지를 동시에 풀빌드하지 않는다(호스트 컴파일 게이트).
- 2026-09-30 기준으로 `agent-room-terminal`·`agent-room-isolator`·`room-release-manager`는 기존 결함 때문에 이 게이트를 통과하지 못한다. 이 셋을 건드리는 변경은 기존 실패 목록과 비교해 새 실패가 없음을 보이는 것으로 대신하고, 그 사실을 변경 설명에 적는다.
- 이 저장소에는 CI 설정과 git 훅이 없다. GitHub에 올린 뒤 자동으로 도는 검사는 없다.
