# 보안 정책

## 보호 대상

- 방 밖의 파일 시스템: 홈의 셸 설정, 다른 방의 폴더, 다른 테넌트의 상태 루트.
- 다른 방의 터미널 세션: 닫기·입력·단발 실행·스냅샷.
- 에이전트 도구의 실제 자격증명: Claude Code keychain 항목(`Claude Code-credentials`)과 그 방 사본.
- 이 저장소 자체: GitHub 공개 저장소(`dalsoop/agent-room-mono`)라서 커밋된 모든 것이 공개된다.

## 벽 세 겹

방 세션은 데몬이 다음 순서로 감싸서 띄운다: 방 `env` 파일 적재 → 새 프로세스 그룹 → 셸(`zsh -r`, open 프리셋만 `zsh`) → seatbelt 프로필이 있으면 `sandbox-exec -p <프로필>`로 감싸기.

1. **제한 셸 `zsh -r`**: PATH를 바꿀 수 없고, `/`가 들어간 명령을 실행할 수 없으며, 파일 리다이렉션이 막힌다. open 프리셋은 제한 셸을 쓰지 않는다.
2. **방 전용 PATH**: 방 `bin/`의 심링크와 기본 셸 폴더(`~/.tenants/_base-bin/`)뿐이다. 링크되지 않은 명령은 존재하지 않는다. open 프리셋은 호스트 PATH를 쓴다.
3. **seatbelt 프로필**(`RoomKit.SeatbeltCompiler`): 기본은 허용(`(allow default)`)이고 다음만 막는다.
   - 쓰기: 홈 전체 쓰기를 막고, 방 폴더·방 `tmp`·`/private/tmp`·`/private/var/folders`·장치 파일 몇 개와 방 설정의 `allowWrite` 경로만 연다. 셸 설정(`.zshrc`·`.zshenv`·`.zprofile`·`.bashrc`·`.bash_profile`·`.profile`)·`.gitconfig`·`.git/hooks`는 허용 목록에 있어도 쓰기를 막는다.
   - 네트워크: `closed`는 `(deny network*)`, `allow`는 방 전용 localhost 프록시 포트 외 outbound 거부, `open`은 제한 없음. env의 `HTTP_PROXY`·`HTTPS_PROXY`·`ALL_PROXY`는 `closed`에서 `http://127.0.0.1:9`, `allow`에서 프록시 주소, `open`에서 빈 값이다.
   - 읽기: 방 설정에 `denyRead`가 없으면 막지 않는다. 기본 프리셋 셋 모두 `denyRead`가 비어 있으므로, 방 세션은 홈의 모든 파일을 읽을 수 있다. 비밀 파일을 방에서 숨겨야 하면 방 설정에 `denyRead`를 명시해야 한다.

데몬의 단발 실행(`exec`)은 seatbelt 프로필이 없으면 명령을 실행하지 않고 exit 126과 "Execution denied (Fail-Closed)"를 돌려준다. 세션 개설(`openSession`)은 요청에 프로필이 없으면 seatbelt 없이 셸을 띄운다. `agent-room-terminal open`은 늘 프로필을 만들어 보내지만, 소켓에 직접 요청하는 클라이언트는 그렇지 않을 수 있으므로 직접 요청하는 도구를 만들 때는 프로필을 반드시 싣는다. `/usr/bin/sandbox-exec`가 없는 호스트에서는 프로필이 있는 세션 개설이 "sandbox-exec is unavailable on this host"로 실패한다.

## 데몬 접근과 세션 인가

- 소켓은 `~/.tenants/_daemon/agent-room-terminal.sock` 하나이고 파일 0600, 디렉터리 0700이다. 같은 사용자 계정의 프로세스만 연결할 수 있다. TCP 수신은 없다(방 `allow` 네트워크용 localhost 프록시만 예외로 포트를 연다).
- 모든 op는 `SessionAuthorizer.allows(requester:target:)`를 지난다. 요청자가 `authority: "commandRoom"`이면 모두 허용한다. 아니면 요청자 세션(`roomSession`, `exec`는 `sessionID`도)의 방 폴더가 대상 방 폴더와 같거나 대상이 요청자 방의 `children/` 아래일 때만 허용하고, 아니면 `foreignRoom`으로 거부한다. 경로는 심링크를 풀고 표준화한 뒤 비교한다.
- 실패 경로: 알 수 없는 세션 id는 `unknown session`, 인가 실패는 `foreignRoom`, 깨진 프레임은 그 연결에만 오류를 보내고 닫는다(서버는 계속 돈다).
- `commandRoom` 권한은 요청 JSON의 문자열 필드일 뿐이고 비밀이나 서명이 없다. 소켓에 닿는 프로세스는 스스로 지휘실이라고 선언할 수 있다. `agent-room-terminal`의 `close`·`exec`·`events`·`handoff` 등 CLI 명령은 늘 지휘실 권한으로 요청한다. 따라서 세션 인가는 방 안 세션이 소켓에 닿지 못한다는 전제(제한 PATH와 seatbelt 네트워크 규칙) 위에서만 방과 방 사이를 가른다.

## 자격증명 사본

- seatbelt는 keychain IPC를 막는다. 그래서 keychain으로 인증하는 도구(현재 `claude`)의 방을 열 때, 방을 여는 CLI·GUI 프로세스(데몬과 seatbelt 밖)가 `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`로 값을 읽어 방 폴더의 `state/claude-config/.credentials.json`에 0600으로 쓰고, 방 env의 `CLAUDE_CONFIG_DIR`가 그 폴더를 가리키게 한다. 새 토큰을 발급하지 않고 사용자의 실제 로그인 값을 복제한다.
- `codex`·`grok`은 파일 기반 인증(`~/.codex/auth.json`, `~/.grok/auth.json`)이라 사본을 만들지 않는다. seatbelt가 그 파일 읽기를 막지 않기 때문이다.
- 사본 삭제: 세션 개설이 실패하면 즉시, 세션이 끝나면 데몬이 세션 종료 처리에서, 방을 닫으면(`close`) CLI가 지운다. 코드에는 vacate·cleanup·dismantle용 삭제 진입점도 있지만 이 저장소 판에서 CLI가 부르는 것은 `close`뿐이다. 지울 때는 파일 크기만큼 0을 덮어쓴 뒤 unlink한다. 같은 폴더의 `projects/`(도구 전사)는 사용량 증거라서 지우지 않는다.
- keychain 읽기에 실패하면 `open` 결과의 `credentialSeed`가 `failed`이고 stderr에 경고가 한 줄 나간다. 방은 그래도 열리며 그 방의 도구는 로그인에 실패할 수 있다.
- toolbelt 방에서 `claude`가 쓸 수 있으면 방 `bin/`에 `security`가 도우미로 링크된다.

## 테넌트 격리

- 상태 루트는 `StateRootKit.resolve`가 정한다: `SWIFT_APP_STATE_ROOT` → 테스트 러너면 임시 폴더 → 테넌트 문맥(`ROOM_TENANT` → `AGENT_TENANT` → `TENANT_ID` → 문맥 파일)이 있으면 `~/.tenants/<슬러그>` → 홈.
- `~/.tenants`는 홈 한 층의 규약이다. 상태 루트 경로에 `.tenants`가 이미 있으면 그 층까지 올라가서 `~/.tenants/personal/.tenants/gujo` 같은 겹친 경로를 만들지 않는다.
- 방 폴더의 테넌트는 방 설정의 테넌트다. 현재 셸의 테넌트로 바꾸지 않는다.

## 기록 대상

- 방 `events.jsonl`: 조립(`assembled`), 점유(`occupied`) 등 방 사건. 한 줄에 사건 하나, 순번(`seq`)·시각·행위자·내용.
- 방 `state/term.log`와 링 버퍼: 세션 출력이 그대로 남는다. 비밀이 화면에 찍히면 그대로 기록된다.
- 데몬 로그(상태 경로 아래): 소켓 오류, 세션 시작·종료, 인가 거부.
- `agent-room-monitor`의 스냅샷 보관(`snapshots/`)과 훅 트레이스(`trace/<세션>.jsonl`).
- `agent-room-isolator`의 결속(`binds.json`, 방 `bind.json`).

## 공개 저장소 정책

- 비밀값(토큰·키·비밀번호·접속 URL의 자격증명 부분)과 keychain 값을 커밋하지 않는다. 테스트 픽스처에도 실제 값을 쓰지 않는다.
- `gujo-product.json`의 상품 번호·카탈로그 URL·지원 URL은 공개 정보로 취급한다.
- 공용 킷에는 사내 호스트 이름과 사설 IP(예: `DBViewerKit`의 기본 점프 호스트)가 기본값으로 들어 있다. 새 코드에 사내 호스트나 사설 주소를 기본값으로 넣지 않는다.

## 하지 않는 것

- 방 세션을 seatbelt 없이 단발 실행하지 않는다.
- 자격증명 사본을 방 폴더 밖이나 0600보다 넓은 권한으로 쓰지 않는다.
- 다른 앱의 원장·상태 파일을 직접 고치지 않는다(원장은 `agent-work-todo`, git 워크트리는 `agent-worktree-control-terminal`).
- 데몬을 LaunchAgent로 상주 등록하지 않는다. 데몬은 CLI가 필요할 때 띄우고, 마지막 세션이 닫히면 유휴 시간 뒤 스스로 끝난다.
