# AgentRoomTerminalCLI

## 범위

PATH CLI `agent-room-terminal` 의 서브커맨드 파싱·출력 봉투, `capabilities`, 훅용 `check`, `daemon start|stop|status`(데몬 실행 파일 기동), `tuning show|set`. 실제 일은 전부 코어 진입점을 부른다.

## 범위 밖

도메인 로직(코어), PTY(데몬), 화면(GUI). 다른 앱 상태 파일 접근.

## 불변식

- Foundation·Core·InteropKit·AppPathsKit·AppScaffoldKit 만 링크한다. AppKit·SwiftTerm 을 링크하면 dual-entry hang 이 재발한다.
- 출력은 `{ok, result}` / `{ok:false, error}` 봉투. 조회는 `--json`.
- 부작용 명령(open·close·handoff·habit promote)은 `--execute` 없이는 계획만 출력하고 부수효과가 0 이다.
- `check` 는 `ROOM_ID` 가 없으면 exit 0. 있으면 절대경로 실행·`env PATH=`·`sh -c`·`bash -c`·`zsh -c`·`python3`·`--tool Agent` 를 exit 2 로 막고 stderr 에 이유를 낸다.
- `capabilities` 의 commands 배열과 실제 서브커맨드 표는 같아야 한다. `stateRoot.env == "SWIFT_APP_STATE_ROOT"` 를 선언한다.
- 데몬 실행 파일은 CLI 와 같은 디렉터리의 `agent-room-terminal-daemon` 에서 찾는다. `.build` 폴백은 없다.

## 패턴

`print` 는 사람용 stdout 에만, 그 줄에 `// allow:debug — CLI human stdout`. 파서는 그룹별 파일(`Commands+Room.swift` 등)로 나눠 함수 80줄 규칙을 지킨다.

## 테스트

봉투 필드, `check` 픽스처 12건(통과 6·차단 6), tuning 라운드트립, dry-run 기본(픽스처 러너로 부수효과 0), 런타임 스모크(daemon start → open --execute → exec → close → daemon stop, 임시 방 폴더·임시 StateRoot).
