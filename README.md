# agent-room-mono

AI Agent Room 시스템 및 터미널 오케스트레이션 모노레포.

## 구성

### Apps (`apps/`)
- **`agent-room-terminal`**: 멀티 에이전트 터미널 룸 오케스트레이터 (GUI / PATH CLI / Daemon).
- **`agent-room-monitor`**: 에이전트 룸 상태 및 프로세스 라이프사이클 모니터.
- **`agent-room-isolator`**: 룸 격리 및 프로세스 샌드박스 경계 제어.
- **`room-release-manager`**: 룸 배포 및 해제 관리자.

### Swift Kits (Root)
- **`swiftkit/`**: RoomKit, StateRootKit, CommandKit 등 핵심 런타임 프레임워크.
- **`swiftkit-terminal/`**: SwiftTerm / Ghostty 기반 가상 터미널 엔진.
- **`swiftkit-appscaffold/`**: 공통 앱 스캐폴딩.
- **`swiftkit-sparkle/`**: 인앱 업데이트 지원 킷.

## 빌드 방법

```bash
cd apps/agent-room-terminal
swift build
```

## 라이선스

MIT License
