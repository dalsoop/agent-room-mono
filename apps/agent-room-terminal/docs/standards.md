# 규칙 — 깨지면 실패하는 것

## 커밋 게이트

- 커밋 훅(native lint)은 **변경 파일 전체**를 검사하고 **경고 하나도 실패**로 친다. `--no-verify` 는 호스트 훅이 완전 차단한다. 우회 경로는 없다: 위반은 실제로 고친다.
- 구조 규칙: 함수 본문 80줄, 파일 1000줄, 타입 본문 400줄, 클로저 50줄, 줄 150자, 파일 if 40개. 넘으면 파일·함수를 실제로 분해한다.
- `print` 는 CLI 사람용 출력에만, 그 줄에 `// allow:debug — CLI human stdout` 주석.
- 오류 삼킴 금지: `try?` 로 결과를 버리는 코드, 빈 catch 는 실패다. 오류는 throw 하거나 응답·로그에 드러낸다.
- 상태 경로 하드코딩 금지: 홈·`~/.tenants` 조립은 StateRootKit / AppPaths 로만. `NSHomeDirectory()`·`expandingTildeInPath` 직접 사용은 실패다.
- 행동이 바뀌는 커밋은 `Packaging/Info.plist` 의 `CFBundleShortVersionString` 을 올려야 한다(marketing-version-bump). 이 앱은 `Versions/` 파일이 없으므로 plist 만 본다.
- 앱 두 개를 한 커밋에 섞으면 에이전트 커밋은 실패한다(cross-app-edit). 공유 kit 변경은 자기 커밋으로 분리한다.
- 같은 코드 블록이 두 앱에 있으면 실패한다(code-clone-stamp). 공용 로직은 swiftkit 또는 소유 kit 로 옮긴다.
- 새 swiftkit 라이브러리는 쓰는 앱이 하나는 있어야 한다(kit-adoption).

## 의존 방향

- `AgentRoomTerminalCLI` 는 Foundation·Core·InteropKit·AppPathsKit·AppScaffoldKit 만 링크한다. AppKit·SwiftTerm 을 링크하면 dual-entry hang 이 재발한다(2026-07-25 사고).
- `AgentRoomTerminalCore` 는 AppKit·SwiftTerm 을 import 하지 않는다. 터미널 파싱은 데몬 타깃, 터미널 뷰는 GUI 타깃.
- 프로세스 실행은 CommandKit. 유일한 예외는 데몬의 PTY 생성(SwiftTerm `LocalProcess`).
- 원장·방 생성·테넌트 정책·위키는 소유 앱 CLI 로만 호출한다. 그 앱들의 상태 파일 경로를 코드에 쓰면 실패다.
- 원장 쓰기는 `LedgerQueue` 한 곳만 지난다. 다른 곳에서 `agent-work-todo placement occupy|tick|handover` 를 직접 부르면 실패다.
- Core 의 외부 CLI 호출은 전부 프로토콜(`LedgerCommandRunning`·`ComplianceChecking`·`WikiPublishing`·`CapabilityLookup`·`ExecRunning`)로 추상화하고 테스트는 픽스처 구현을 쓴다. 테스트가 실제 원장·위키·`~/.tenants` 를 건드리면 실패다.

## CLI 계약

- 모든 명령은 `{ok, result}` / `{ok: false, error}` 봉투(InteropKit). 조회는 `--json`.
- 부작용 명령(open·close·handoff·habit promote)은 기본 dry-run(계획 출력)이고 `--execute` 로만 실행한다.
- `capabilities --json` 은 commands 배열(각 `json`·`dryRun` 표시)·depends(agent-work-todo·agent-room-monitor·agent-tenant-isolation-manager·agent-wiki·zsh)·`stateRoot.env == "SWIFT_APP_STATE_ROOT"` 를 선언한다. 같은 계약이 `interop-expects.json` 에 있다.
- 다른 앱 CLI 의 stdout 은 설치본 경고가 앞에 붙을 수 있으므로 JSON 파싱은 첫 `{` 또는 `[` 부터 자른다.

## 4면

모든 CLI 명령은 GUI 표면(노드 컨텍스트 메뉴·상세 패널·설정)을 갖고, GUI 는 Core 의 같은 진입점을 호출하며, 앱 상태는 StateMirror 로 게시한다. CLI 에만 있는 기능은 미완성이다.

## 검증

패키지 테스트 exit 0 · `agent-lint-catalog check --changed-since origin/main` 차단 0·경고 0 · `agent-cli-scaffold quality --app agent-room-terminal` 통과 · 런타임 스모크(daemon start → open --execute → exec → close → daemon stop). 빌드·테스트 출력을 `tail`·`head` 로 가리지 않는다. 같은 턴에 두 패키지를 동시에 풀빌드하지 않는다.

## 문안

UI 문안은 L10n 키로만(리터럴 금지). 「잠자기」(「수면」 금지). 앱·기능 이름은 풀네임 객체명.
