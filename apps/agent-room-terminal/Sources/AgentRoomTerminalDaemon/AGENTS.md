# AgentRoomTerminalDaemon

## 범위

유닉스 소켓 서버, PTY 세션(SwiftTerm `LocalProcess`), 세션 표, 세션 인가 적용, 링 버퍼·`state/term.log` 흘림, attach 스트림·input, 유휴 종료, 세대 번호, SIGTERM 시 전 세션 정상 종료, 데몬 로그.

## 범위 밖

방 폴더 조립·예산·습관·원장 큐의 정책(코어), CLI 파싱, 화면. 이 타깃은 PATH CLI 가 아니며 사용자가 직접 실행하지 않는다.

## 불변식

- 모든 op 는 `authorize` → `SessionAuthorizer.allows` 를 지난다. 새 op 를 추가할 때 이 경로를 건너뛰면 결함이다.
- `openSession`·`listSessions` 는 지휘실 권한(`authority: "commandRoom"`)이 있어야 한다.
- 소켓 파일 0600, 디렉터리 0700. TCP 를 열지 않는다.
- PTY 읽기는 세션별 직렬 큐에서만, 파싱은 헤드리스 `Terminal`. 메인 스레드에서 read 하지 않는다.
- 유휴 종료는 세션 표가 빈 시각부터 센다. 세션이 하나라도 있으면 끝나지 않는다.
- catch 에서 무응답으로 끝내지 않는다: 오류 응답 전송 시도 + `DaemonLog` 기록 + 서버 지속. 프레이밍 오류는 그 연결만 닫는다.
- `attach` 연결은 닫지 않고 `output`·`exit` 이벤트를 흘리며 같은 연결의 `input` 을 PTY 에 쓴다. 다중 구독 허용.

## 패턴

세션 시작: env 파일 로드 → 새 pgid → 셸(`zsh -r` 또는 `zsh`) → seatbelt 프로필이 있으면 `sandbox-exec -p <profile>` 로 감싸기 → 세션 id 발급·`ROOM_SESSION` 주입. 종료: SIGTERM → 5초 → SIGKILL. 세대 번호는 기동마다 증가하고 모든 응답에 실린다.

## 테스트

프레이밍 라운드트립, 소켓 왕복(임시 소켓), `zsh -r` 절대경로 거부, 링 초과 흘림, 유휴 종료(주입 시계), 타 방 세션 거부, 세대 증가, attach 다중 구독 수신, 깨진 프레임 뒤 다음 연결 정상. seatbelt 실제 적용은 `sandbox-exec` 가 있는 Mac 에서만.
