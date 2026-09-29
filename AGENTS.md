# agent-room-mono

한 대의 Mac에서 여러 AI 에이전트 세션을 "방(room)"에 가두고 관찰하는 macOS 앱 모노레포다. 방 터미널(`agent-room-terminal`), 방 관측판(`agent-room-monitor`), 방과 git 워크트리 결속기(`agent-room-isolator`) 세 앱이 방 체제를 이루고, 방과 무관한 파티룸 배포 앱(`room-release-manager`)이 함께 들어 있다. 앱은 모두 독립 SwiftPM 패키지이고 같은 저장소의 공용 킷 패키지 네 개(`swiftkit`, `swiftkit-terminal`, `swiftkit-appscaffold`, `swiftkit-sparkle`)를 상대 경로로 끌어 쓴다. 네 앱은 Gujo 스토어 카탈로그(`gujo-product.json`의 상품 번호 241·246·247·248)에 묶여 있고, 저장소는 공개 GitHub 저장소(`dalsoop/agent-room-mono`)다.

## 프로젝트 구조

```
agent-room-mono/
├── CLAUDE.md / AGENTS.md                     ← 진입점(같은 내용)
├── docs/
│   ├── architecture.md                       ← 앱·킷 구성, 의존 방향, 방 열기 흐름, 외부 CLI
│   ├── business-rules.md                     ← 방·벽 프리셋·세션 역할·방 개념 검증·파티룸 빌드 규칙
│   ├── security.md                           ← 벽 세 겹, 데몬 인가, 자격증명 사본, 공개 저장소 정책
│   ├── standards.md                          ← 깨지면 실패하는 규칙(타깃 링크, 상태 경로, 봉투, 검증 게이트)
│   ├── engineering-notes.md                  ← 함정(툴체인, 트레잇, 엔진 팩토리, 저장 경로 두 갈래)
│   ├── operations.md                         ← 빌드·테스트 절차, 데몬·상태 경로, 환경 변수
│   ├── contracts.md                          ← 네 CLI의 명령·입출력·오류, 데몬 소켓, 방 폴더 계약
│   └── tracking/
│       ├── status.md                         ← 만든 것과 검증한 것, 남은 것
│       ├── findings.md                       ← 미해결 문제(빌드 깨짐, 이름 불일치, 문서 낡음)
│       └── decisions/
│           ├── index.md                      ← 결정 기록 색인
│           └── NNNN-*.md                     ← 결정 기록
├── apps/
│   ├── agent-room-terminal/
│   │   ├── CLAUDE.md / AGENTS.md             ← 방 터미널 앱 진입점(앱 자체 docs/ 묶음을 가진다)
│   │   ├── docs/                             ← 방 터미널 앱 전용 문서 묶음
│   │   └── Sources/<타깃>/AGENTS.md          ← Core·Daemon·CLI·GUI 타깃별 규칙
│   ├── agent-room-monitor/AGENTS.md          ← 방 관측판(소유 CLI로만 읽고 조작)
│   ├── agent-room-isolator/AGENTS.md         ← 방 개념 검증 → 워크트리 → 원장 → 방 문서 발행
│   └── room-release-manager/AGENTS.md        ← 파티룸 Flutter 앱 멀티 플랫폼 빌드
├── swiftkit/AGENTS.md                        ← 공용 킷 244개 모음(방 관련 킷 포함)
├── swiftkit-terminal/AGENTS.md               ← 터미널 엔진 추상화와 SwiftTerm·Ghostty 구현
├── swiftkit-appscaffold/AGENTS.md            ← 앱 공용 스캐폴드와 트레잇(GujoManaged·SelfUpdating·Telemetry)
└── swiftkit-sparkle/AGENTS.md                ← Sparkle 자동 업데이트 래퍼
```

## 절대 규칙

1. PATH CLI 타깃(`agent-room-terminal`, `agent-room-monitor`, `agent-room-isolator`, `room-release-manager`)의 코드는 AppKit·SwiftUI를 import하지 않고, 타깃 의존 목록에 UI 킷(`*UIKit`, `SettingsUIKit` 등)이나 터미널 엔진(SwiftTerm·Ghostty 구현)을 직접 넣지 않는다. 터미널 엔진은 데몬 타깃(SwiftTerm)과 GUI 타깃(Ghostty)에만 둔다. 어기면 GUI·CLI 이중 진입 앱에서 CLI가 멈추는 사고(2026-07-25)가 재발한다.
2. 방 세션의 벽을 약하게 만들지 않는다. 세션은 `zsh -r`(open 프리셋만 `zsh`) + 방 전용 PATH + seatbelt 프로필 안에서 돌고, 데몬의 단발 실행(`exec`)은 seatbelt 프로필이 없으면 실행을 거부한다(exit 126). 프로필 없이 실행하는 경로를 새로 만들지 않는다.
3. 상태 경로는 `StateRootKit`/앱별 `AppPaths`로만 조립한다. `NSHomeDirectory()`·`homeDirectoryForCurrentUser`·`expandingTildeInPath`로 홈을 직접 조립하는 새 코드를 넣지 않는다. 테넌트가 섞이면 한 테넌트의 방 쓰기가 다른 테넌트 루트에 떨어진다.
4. 이 저장소 밖 앱의 원장·상태는 그 앱의 CLI로만 읽고 쓴다(`agent-work-todo`, `agent-worktree-control-terminal`, `agent-tenant-isolation-manager` 등). 그 앱들의 상태 파일 경로를 코드에 새로 쓰지 않는다.
5. 공개 저장소다. 토큰·키·자격증명 원문, 실제 keychain 값, 사내 호스트의 접속 정보를 커밋하지 않는다.

## 일하기 전에 읽을 것

- 항상: `docs/standards.md`, `docs/engineering-notes.md`, 그리고 손댈 앱이나 킷의 `AGENTS.md`.
- 빌드부터 확인한다: 2026-09-30 기준으로 `agent-room-terminal`·`room-release-manager`는 컴파일이 깨져 있고 `agent-room-isolator`는 없는 로컬 패키지를 참조해 해석부터 실패한다. 어떤 변경이든 먼저 `docs/tracking/findings.md`의 빌드 항목을 읽고 기존 실패와 새 실패를 구분한다.
- 방 벽·seatbelt·네트워크 프록시를 건드리기 전에: `docs/security.md`의 벽 세 겹 절과 `swiftkit/AGENTS.md`의 `SeatbeltCompiler` 불변식.
- 방 폴더 구조나 경로를 바꾸기 전에: `docs/contracts.md`의 방 폴더 절과 `docs/engineering-notes.md`의 저장 경로 두 갈래 항목. 정본 경로(`~/.tenants/<테넌트>/rooms/<방id>`)와 옛 2단 경로 탐색이 함께 살아 있다.
- 자격증명 주입(`AgentCredentialInjector`)을 건드리기 전에: `docs/security.md`의 자격증명 사본 절.
- `apps/agent-room-terminal`의 앱 전용 `docs/`는 swift-app-mono 시절에 쓰인 부분이 많다. 그 문서와 코드가 다르면 코드를 따르고 차이를 `docs/tracking/findings.md`에 적는다.
- 공용 킷(`swiftkit*`)을 바꾸기 전에: 같은 킷이 swift-app-mono에도 따로 있다는 `docs/tracking/findings.md`의 사본 분기 항목.

## 문제가 생기면

즉시 사용자에게 보고할 것:
- 방 안 세션이 벽 밖에서 명령을 실행했거나 방 밖 경로에 쓴 흔적
- 세션 인가를 건너뛰어 한 방의 세션이 다른 방 세션을 닫거나 입력한 흔적
- 방 폴더의 `state/claude-config/.credentials.json` 같은 자격증명 사본이 방 종료 뒤에도 남았거나 로그·스냅샷·커밋에 들어간 흔적
- 한 테넌트의 방 파일이 다른 테넌트 루트에 쓰인 흔적
- 공개 저장소에 비밀값이 커밋된 흔적

그 밖의 문제는 `docs/tracking/findings.md`에 조건·증상·영향·지금 못 고치는 이유·접근 방법을 적는다.
