# 보안 정책

## 보호 대상

방 밖의 파일 시스템(다른 방·테넌트 정본·홈), 다른 방의 세션, 원장(agent-work-todo)·테넌트 정책·위키의 정본, 그리고 세션 기록에 들어 있을 수 있는 비밀값.

## 세션 인가

- 데몬의 모든 op(openSession · closeSession · exec · attach · input · snapshot · listSessions · tuning · ensureNetworkProxy)는 `SessionAuthorizer.allows(requester:target:)` 를 지난다. 우회 경로는 없다.
- 요청자는 `roomSession`(자기 세션 id) 또는 `authority: "commandRoom"` 으로 식별된다. 세션은 자기 방과 자기가 연 자식 방만 조작할 수 있고, 타 방은 `foreignRoom` 으로 거부된다. 지휘실 권한은 전부 허용된다.
- 지휘실 권한에는 별도 비밀이 없다. 소켓 파일이 소유자 전용(0600, 디렉터리 0700)이므로 같은 사용자 계정만 데몬에 닿는다. 다른 계정·네트워크에서는 접근 불가다.
- 실패 경로: 세션 id 없음 → 요청 거부, 알 수 없는 세션 → `unknown session`, 인가 실패 → `foreignRoom`, 깨진 프레임 → 그 연결만 오류 응답 후 종료(서버 지속).

## 벽 — 세 겹

1. 제한 셸 `zsh -r`: PATH 변경 불가, `/` 가 포함된 명령 실행 불가(`restricted`), 파일 리다이렉션 불가. open 프리셋만 일반 `zsh`.
2. PATH: 방 `bin/` + 기본 셸 폴더뿐. 허용 밖 명령은 존재하지 않는다(`command not found`).
3. seatbelt: `sandbox-exec` 프로필. 쓰기 허용 = 방 폴더·`/private/tmp`·`/private/var/folders`, 그 밖은 거부. 자식 방은 자식 폴더로만.
훅 `check` 는 보조다: 방에 앉은 Claude Code·Grok 세션의 절대경로 실행·`env PATH=`·`sh -c`·`zsh -c`·`python3`·서브에이전트 도구 호출을 exit 2 로 막는다. 훅 표면이 없는 도구(Codex·Antigravity)는 세 겹만으로 선다. 훅만으로 앉은 세션은 `hookOnly` 로 기록되고 화면에 "약한 벽" 이 붙는다 — 그 상태를 정상으로 취급하지 않는다.

## 네트워크

`walls.network` 는 `closed` · `allow` · `open` 이다. `closed` 는 env 의 `HTTP_PROXY`·`HTTPS_PROXY`·`ALL_PROXY` 를 `http://127.0.0.1:9` 로 고정한다. `open` 은 프록시를 비운다. `allow` 는 데몬이 방마다 localhost HTTP 프록시를 띄우고 그 포트만 seatbelt outbound 로 연다. 허용 도메인은 설계도가 주고, 거부는 `state/network-denied.jsonl` 에 남긴다.

## 비밀값

이 앱은 비밀값을 저장하지 않는다. 사용량 어댑터는 도구 세션 기록(Claude transcript·Codex 세션 파일·Grok ACP 로그)을 읽기 전용으로 읽고 토큰 수만 남긴다(본문은 저장하지 않는다). 터미널 링 버퍼와 `state/term.log` 에는 세션 출력이 그대로 남으므로, 비밀을 다루는 방은 터미널 안쪽을 veilkey 의 PTY 마스킹으로 한 번 더 감싸는 것을 전제로 한다(이 앱 밖의 선택 층).

## 기록 대상

원장 점유·틱·handover 전이(agent-work-todo 가 기록), 방 폴더 `handoff/` 의 빈병, `state/usage.jsonl` 의 사용량, 데몬 로그(AppPaths 아래, 소켓 오류·세션 시작·종료·인가 거부).

## 하지 않는 것

kubectl·mysql·psql·tinker·SQL 직접 실행, 다른 앱 상태 파일 직접 쓰기, LaunchAgent 등록, 시뮬레이션에서 dry-run 계약 없는 명령 실행. 방 네트워크 벽의 localhost allowlist 프록시만 예외로 TCP 를 연다.
