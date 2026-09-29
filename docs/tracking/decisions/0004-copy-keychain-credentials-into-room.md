# 0004. keychain 자격증명을 방 폴더에 파일로 복제한다

**상황**: 방 세션은 seatbelt 안에서 돈다. 2026-09-04 실측에서 seatbelt가 macOS keychain IPC를 막아, keychain으로 인증하는 도구(Claude Code)가 방 안에서 `/login`에 항상 실패했다. 파일 읽기는 seatbelt가 막지 않는다(`AgentCredentialInjector.swift` 주석).

**결정**: 방을 여는 프로세스(방 밖, keychain 접근 가능)가 keychain 값을 읽어 방 폴더 `state/<도구>-config/.credentials.json`에 0600으로 쓰고, 방 env의 도구 config 디렉터리 변수(`CLAUDE_CONFIG_DIR`)가 그 폴더를 가리키게 한다. 방을 닫거나 세션이 끝나거나 개설이 실패하면 파일을 0으로 덮어쓴 뒤 지운다. 같은 폴더의 도구 전사는 지우지 않는다.

**대안**: 기록된 대안 비교는 없다. 코드 주석은 이 방식이 새 토큰 발급도 사람 개입도 요구하지 않는다는 점을 근거로 든다. 파일 기반 인증을 쓰는 도구(`codex`, `grok`)는 복제가 필요 없어서 대상에서 뺐다.

**결과**: 방이 열려 있는 동안 사용자의 실제 로그인 값 사본이 방 폴더에 있다. seatbelt가 읽기를 막지 않으므로 같은 사용자 계정의 다른 프로세스도 그 파일을 읽을 수 있다. 사본 삭제가 실패하면 stderr에만 남으므로, 방을 닫은 뒤 사본이 없는지 확인해야 한다. 도구별 전략은 `AgentCredentialInjector.strategies` 표 한 곳에서 늘린다.
