# AgentRoomWorktree-swift

일반 창 앱(독 앱 — 메뉴바 없음). 공유 `swiftkit`(CommandKit / LocalizationKit) 위에 빌드된다.

이 앱은 태어날 때부터 4면 계약(GUI + Core + CLI + StateMirror)을 갖춘다 —
`interop.json`, `StateMirrorKit` 게시 지점(앱 시작 시 1회 게시 포함), CLI `capabilities`,
사용법 온보딩(한 번만 표시 — 질문형 입력 위저드 금지). 남은 절차(도메인 로직,
아이콘, ship, MR)는 `agent-cli-scaffold checklist --app agent-room-worktree` 이 순서대로 알려준다.

상태 경로는 `Sources/AgentRoomWorktreeCore/AppPaths.swift` 가 `StateRootKit` 으로만 조립한다 —
앱 상태 디렉터리 `AppPaths.stateDirectory()`(기본 `~/.agent-room-worktree/`, 테넌트 컨텍스트면
`~/.tenants/<t>/.agent-room-worktree/`)와 sqlite 정본 `AppPaths.sqliteFile` 모두 같은 루트 아래다.
`NSHomeDirectory()`·`homeDirectoryForCurrentUser`·`expandingTildeInPath` 로 홈을 직접 조립하지
않는다(lint `hardcoded-state-root`). 새 상태 파일은 `AppPaths.stateFile("…")` 로 만든다.

## 빌드 / 테스트

    swift build
    swift test

## 구조

- `Sources/AgentRoomWorktree/` — SwiftUI 주 창(`MainView`) + 사용법 온보딩 + 설정(⌘,) + i18n.
- `Sources/AgentRoomWorktreeCore/` — 도메인 로직(시스템 명령 호출/파싱). `CommandRunning` 주입으로 테스트 가능.

방 개념을 먼저 잠그고 git 워크트리를 결속한 뒤 방 폴더에 MD 를 발행한다.
계약: `docs/rooms/room-worktree-contract.md`. **CLI 에 추가하는 모든 연산은 GUI 표면도 함께**(4면 계약).
