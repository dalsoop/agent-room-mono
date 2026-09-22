# 함정

## 툴체인

- 증상: `swift test --package-path apps/agent-room-terminal-swift` 가 Package.swift 매니페스트 단계에서 `sandbox-exec` / posix_spawn ENOENT 로 실패한다. 원인: 이 Mac 의 기본 PATH 에 있는 `swift` 는 offload 래퍼라 매니페스트를 interpret 한다. 대응: Xcode 툴체인 PATH 로 `env -i` 실행하거나 `SWIFTPM_ENABLE_SANDBOX=0`, `SWIFT_EXEC` 를 비운다. 검증: `swift --version` 이 Xcode 툴체인 경로를 가리키는지 본다.
- 증상: SwiftTerm 을 처음 받는 빌드가 오래 걸린다. 원인: `swift package resolve` 가 네트워크로 SwiftTerm 1.20 대를 받는다(핀은 `from: "1.15.0"`). 대응: 첫 빌드는 한 번만, 워크트리를 나누면 각자 받는다.

## 커밋 훅

- 증상: 코드는 맞는데 커밋이 막힌다. 원인: 변경 파일 전체 검사라 그 파일의 기존 부채(긴 함수·한글 리터럴)가 함께 걸린다. 대응: 새 코드는 새 파일(extension)로 분리해 옛 파일을 건드리지 않거나, 옛 부채를 실제로 분해한다. 검증: `git ls-files -m -o --exclude-standard apps/agent-room-terminal-swift | agent-lint-catalog check --paths-from-stdin --json` 에서 경고 0.
- 증상: 병합할 때 `Packaging/Info.plist` 가 충돌한다. 원인: 작업마다 커밋 훅이 마케팅 버전 상승을 요구해 서로 다른 브랜치가 같은 줄을 올린다. 대응: 충돌은 항상 더 높은 버전으로 해소하고, 한 바퀴에 여러 작업이 있으면 마지막에 한 번 더 올린다.
- 증상: 두 앱에 같은 로직을 넣은 병렬 작업 뒤 `code-clone-stamp` 가 뜬다. 대응: 공용 로직은 처음부터 kit 작업으로 자른다(RoomWallKit·agent-wiki-kit 사례).

## 데몬·세션

- `openSession`·`listSessions` 는 지휘실 권한(`authority: "commandRoom"`)이 없으면 `foreignRoom` 으로 거부된다. 첫 세션을 여는 쪽은 언제나 CLI·GUI(지휘실)다. 방 안 세션은 자기 `ROOM_SESSION` 을 `roomSession` 으로 보낸다.
- `attach` 는 연결을 닫지 않는 스트림이다. 같은 연결로 `input` 프레임을 보내고 `output`·`exit` 이벤트를 받는다. 한 요청·한 응답 클라이언트로 attach 를 부르면 첫 응답만 받고 스트림을 놓친다.
- 제한 셸 `zsh -r` 은 `/etc/zshrc` 를 여전히 읽는다. `locale` 같은 명령이 PATH 에 없으면 시작 시 `command not found` 한 줄이 링 버퍼 첫 줄에 남는다. 방 벽과 무관한 소음이니 스냅샷 비교에서 첫 줄은 제외한다.
- 링 스냅샷은 개행 없는 대기 프롬프트도 한 줄로 포함한다. 마지막 줄이 프롬프트면 명령이 끝난 것이다.
- seatbelt 프로필의 허용 쓰기 경로에 `/private/var/folders` 가 있어 테스트 임시 경로는 막히지 않는다. 샌드박스 거부를 테스트하려면 임시 폴더 밖 경로로 쓴다.
- 유휴 종료는 마지막 세션이 닫힌 시각부터 센다. 세션이 하나라도 살아 있으면 데몬은 끝나지 않는다. 데몬 세대 번호(`generation`)가 바뀌면 그전 세션은 전부 사라진 것이다.

## 원장 CLI

- `agent-work-todo placement tick` 은 8자리 축약 id 를 거부한다. 전체 UUID 를 넘긴다.
- 설치본 `agent-work-todo`·`agent-room-monitor`·`agent-tenant-isolation-manager` 는 소스보다 낡았다는 경고를 stdout 앞에 붙인다. JSON 은 첫 `{` 부터 파싱한다. 새 명령(`world ensure`·`check`·`placement handover`)은 설치본에 없으므로 브랜치에서 빌드한 실행 파일로 돌린다.
- 방 생성 원자 명령은 `agent-work-todo placement spawn-room … --via agent-room-monitor` 형식이다. `agent-room-monitor mutate spawn-room` 을 직접 부르지 않는다.

## 검증 체크리스트 — 벽이 서는지

1. 방 터미널에서 `echo $PATH` → 방 `bin/` 과 기본 셸 폴더뿐인지.
2. `which kubectl` → `not found`.
3. `/usr/local/bin/kubectl` → `zsh: …: restricted`.
4. `echo x > ../outside.txt` → `writing redirection not allowed in restricted mode`, 파일이 방 밖에 생기지 않았는지.
5. 다른 세션 id 로 `closeSession` → `foreignRoom`.
6. 마지막 세션 닫은 뒤 60초 → 데몬 프로세스와 소켓 파일이 사라졌는지.
