# Agent Room Terminal

에이전트 세션의 자유를 **방(room)** 으로 통제하는 macOS 앱이다. 방 하나 = 테넌트 폴더 하나 + 그 폴더 안에서만 도는 전용 터미널 하나 + 벽. 지휘 세션도 하위 에이전트도 그 터미널 안에서 살고, 방을 나가는 길은 판정 명령·blocked 선언·자식 방 초안·빈병(handoff) 넷뿐이다. 이 Mac 한 대, 테넌트 넷(personal·gujo·wife·silneobal), 동시에 살아 있는 방 30개 안팎이 규모다. swift-app-mono 함대의 에이전트 운영 앱이며 GUI·Core·CLI·데몬 네 면으로 이루어진다.

## 프로젝트 구조

```
apps/agent-room-terminal-swift/
├── CLAUDE.md / AGENTS.md            ← 진입점(같은 내용)
├── docs/
│   ├── architecture.md              ← 네 면(GUI·Core·CLI·데몬)과 소켓·원장·정책 앱의 연결
│   ├── business-rules.md            ← 방·벽·자식·빈병·예산·습관·시뮬레이션의 규칙
│   ├── security.md                  ← 세션 인가·샌드박스·소켓·비밀 정책
│   ├── standards.md                 ← 깨지면 실패하는 규칙(커밋 게이트·의존 방향·CLI 계약)
│   ├── engineering-notes.md         ← 함정(툴체인·커밋 훅·세션 규약)
│   ├── operations.md                ← 빌드·테스트·데몬 기동·방 세우기 절차
│   ├── contracts.md                 ← CLI 명령·소켓 프레임·폴더 구성 계약
│   └── tracking/
│       ├── status.md                ← 만든 것·남은 것
│       ├── decisions/index.md       ← 결정 기록 색인
│       └── findings.md              ← 미해결 문제
├── Sources/AgentRoomTerminalCore/AGENTS.md     ← 방·데몬 클라이언트·원장 큐·예산·습관 코어
├── Sources/AgentRoomTerminalDaemon/AGENTS.md   ← PTY 를 쥔 실행 데몬
├── Sources/AgentRoomTerminalCLI/AGENTS.md      ← PATH CLI (Foundation 만)
└── Sources/AgentRoomTerminal/AGENTS.md         ← 트리 캔버스 GUI
```

## 절대 규칙

1. 벽은 세 겹(제한 셸 `zsh -r` · 방 `bin/` 전용 PATH · seatbelt 파일 샌드박스)이 주고, 훅 `check` 는 보조다. 훅을 주 벽으로 올리거나 세 겹 중 하나를 빼지 않는다.
2. 다른 앱의 상태 파일을 직접 읽거나 쓰지 않는다. 원장은 `agent-work-todo` CLI, 방 생성은 `agent-room-monitor mutate spawn-room`, 테넌트 정책은 `agent-tenant-isolation-manager` CLI, 위키는 `agent-wiki` CLI 로만. 원장 쓰기는 데몬 안 단일 직렬 큐만 지난다.
3. 자식은 부모·형제 방을 조작할 수 없다. 세션 인가는 모든 데몬 op 가 `SessionAuthorizer.allows` 를 지나며, 자기 방과 자기가 연 자식 방만 허용된다.
4. 시뮬레이션은 소유 앱 `capabilities` 에 `dryRun: true` 계약이 있는 명령만 실제 실행한다. 예외 플래그는 없다.
5. PATH CLI 타깃은 Foundation 만 링크한다. SwiftTerm·AppKit 은 데몬 타깃과 GUI 타깃에만 있다. 프로세스 실행은 CommandKit 이며, 유일한 예외는 데몬의 PTY 생성(SwiftTerm `LocalProcess`)이다.

## 일하기 전에 읽을 것

- `docs/standards.md` 와 `docs/engineering-notes.md` 를 먼저 읽는다. 커밋은 변경 파일 전체를 검사하고 경고 하나도 실패로 치며, 마케팅 버전 상승을 요구한다.
- 데몬 프로토콜을 바꾸기 전에 `docs/contracts.md` 의 소켓 프레임 절과 `Sources/AgentRoomTerminalCore/AGENTS.md` 의 인가 불변식을 읽는다.
- 방 폴더 구성을 바꾸기 전에 `docs/business-rules.md` 의 방 폴더·프리셋 절을 읽는다. 폴더 조립은 멱등이어야 한다.
- 원장 필드(설계도 `wallPreset`·`agentTools`, 방 `wallMode`·successor 필드, 빈병 `predecessor`·`budget`)를 쓰기 전에 `docs/contracts.md` 의 원장 계약 절을 읽는다. 정본은 `apps/agent-work-todo` 다.

## 문제가 생기면

즉시 사용자에게 보고할 것: 방 안 세션이 벽 밖 명령을 실행한 흔적, 자식 세션이 부모 방을 조작한 흔적, 시뮬레이션이 dry-run 계약 없는 명령을 실행한 흔적, 다른 앱 상태 파일을 직접 쓴 코드. 그 밖의 문제는 `docs/tracking/findings.md` 에 조건·증상·영향·왜 지금 못 고치는지를 적는다.
