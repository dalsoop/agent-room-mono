# swiftkit-terminal

터미널 엔진의 프로토콜·값 타입과 두 구현을 담은 킷 패키지다. 제품은 셋이다: `TerminalEngineKit`(원격 의존 없음), `TerminalEngineSwiftTerm`(SwiftTerm 1.13.0 고정), `TerminalEngineGhostty`(libghostty-spm 커밋 리비전 고정, Metal 렌더러와 인메모리 스트림). `swiftkit`의 CommandKit·InteropKit·StateRootKit을 의존한다.

## 범위

- `TerminalEngineKit`: 엔진 프로토콜(`TerminalEngine`, `@MainActor`), 이벤트 위임(`TerminalEngineEvents`), 실행 문맥(`TerminalLaunch`: cwd·command·env·외형·tmux·pane 샌드박스), 외형(`TerminalAppearance`), 스크롤 설정, tmux 백킹(`TmuxBacking`), pane 격리(`PaneSandbox`, `PaneEnvInjector`), 인메모리 바이트 스트림(`TerminalByteStream`), 엔진 팩토리(`TerminalEngineFactory`), 테스트용 `MockTerminalEngine`, kitty 키보드 프로토콜 값.
- `TerminalEngineSwiftTerm`: SwiftTerm 기반 엔진과 대화형 뷰, 외형 적용. `registerSwiftTerm()`으로 팩토리에 등록한다.
- `TerminalEngineGhostty`: `TerminalByteStream`을 받아 그리는 Ghostty 엔진. `registerGhostty()`로 팩토리에 등록한다.

## 범위 밖

- 방·벽·세션 인가·데몬 프로토콜(방 터미널 앱의 일이다).
- 프로세스 수명 관리 정책. 이 패키지의 pane 샌드박스는 전용 홈과 env만 만들고 seatbelt를 걸지 않는다.
- `swiftkit` 본체. 이 패키지를 `swiftkit`이 의존하면 안 된다.

## 불변식

- `TerminalEngineKit`은 원격 패키지를 의존하지 않는다. SwiftTerm·Ghostty 타입은 각 구현 타깃 밖으로 새지 않는다.
- SwiftTerm은 `exact: "1.13.0"`, libghostty-spm은 `revision:`으로 고정한다. 버전을 올리면 두 엔진 테스트와 방 터미널 앱 빌드를 함께 돌린다.
- `TerminalEngineFactory.make`는 등록되지 않은 종류를 받으면 오류 없이 `MockTerminalEngine`을 돌려준다. 기본 종류는 `ghostty`다. 팩토리를 쓰는 앱은 시작 시 `register…()`를 불러야 하고, 등록 전에 `make`를 부르면 빈 뷰가 나온다.
- `PaneSandbox.make`는 StateRootKit 루트의 `.terminal/panes/<paneId>`와 그 안 `inbox/`를 만들고 `TERMINAL_PANE_ID`·`TERMINAL_PANE_HOME`을 env로 준다. 전역 계정 전환은 하지 않고 config 디렉터리 env만 쓴다.
- `PaneEnvInjector.wrap`은 명령이 비면 로그인 셸을 다시 exec하고, 명령이 있으면 export 뒤 `exec <명령>`을 붙인다. 모든 값은 작은따옴표로 감싼다(`shellQuote`).
- 엔진 메서드는 메인 액터에서만 부른다.

## 구현 패턴

- 새 엔진은 `TerminalEngine`을 구현하는 타깃을 따로 만들고 `TerminalEngineKind`에 case를 더한 뒤 `register…()` 정적 함수를 둔다.
- 데몬처럼 PTY를 다른 프로세스가 쥐는 경우, 화면 쪽은 `TerminalByteStream`으로 바이트를 받아(`receive`) 엔진에 넘기고, 입력은 `onInput`으로 돌려보낸다. 방 터미널 GUI가 이 방식으로 `GhosttyTerminalEngine(stream:)`을 직접 만든다.

## 테스트

- `swift test`: XCTest 13건(TerminalEngineKitTests 12, TerminalEngineGhosttyTests 1). 2026-09-30 통과.
- `TerminalEngineKit` 변경은 순수 함수(`PaneEnvInjector`, `PaneSandbox.paneId`, tmux 인자) 테스트로 확인한다. 엔진 구현 변경은 `MockTerminalEngine`으로 호출 순서를 확인하고, Ghostty는 인메모리 스트림 테스트로 확인한다.
- `PaneSandbox.make`는 실제 폴더를 만들므로 테스트에서 `SWIFT_APP_STATE_ROOT`를 임시 폴더로 준다.
