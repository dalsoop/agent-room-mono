# agent-room-isolator

## 목표
에이전트 작업 공간의 프로세스 및 자원 격리를 엄격하게 보장하는 샌드박스 관리 도구입니다.

## 지금 범위
- 저장 경로: AppPaths
- GUI: Window
- CLI: agent-room-isolator
- **없음**:

## CLI
이 앱의 도메인 조작은 CLI가 문이다(App CLI First). 상태 파일 직접 수정·GUI 클릭 우회 금지.
```bash
agent-room-isolator capabilities
agent-room-isolator --help
```

## 상태
- 상태 루트: `AppPaths.stateDirectory()` → StateRootKit(`~/.agent-room-isolator/`).
- StateMirror: `~/.swift-app-state/agent-room-isolator.json`
- 헬스 펄스: `HealthPulse.publish(app:)` → `~/.swift-app-state/pulse/agent-room-isolator.pulse`
