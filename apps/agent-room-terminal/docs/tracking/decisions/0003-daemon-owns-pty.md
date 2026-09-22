# 0003 — 실행 데몬이 PTY 를 쥔다, 상주 등록은 없다

**상황**: 앱 창을 닫아도 방 터미널이 살아 있어야 한다. 이 Mac 은 상주 데몬(LaunchAgent KeepAlive)을 줄이는 규칙이 있다. PATH CLI 는 Foundation 만 링크해야 하는데 터미널 에뮬레이터(SwiftTerm)는 화면 모듈과 묶여 있다.

**결정**: 세 번째 실행 파일 `agent-room-terminal-daemon` 이 PTY·프로세스 그룹·원장 쓰기 큐를 소유한다. 필요할 때 CLI·앱이 띄우고 마지막 세션이 닫힌 뒤 유휴 60초면 스스로 끝난다. LaunchAgent 등록 없음. 데몬만 SwiftTerm 을 링크하고 PATH CLI 는 Foundation 만 링크한다. PTY 생성은 SwiftTerm `LocalProcess` 로 하며 이것이 "프로세스는 CommandKit" 규칙의 유일한 예외다.

**대안**: (a) 앱이 PTY 를 쥠 — 창을 닫으면 방이 죽는다. (b) LaunchAgent 상주 — 호스트 규칙 위반, 렉 사고 재발. (c) PTY 를 posix_openpt 로 직접 구현 — 구현량이 늘고 파서를 따로 만들어야 한다.

**결과**: 앱·CLI 는 소켓 클라이언트다. 데몬이 죽으면 살아 있던 방은 blocked 로 기록되고 세대 번호가 바뀐다.
