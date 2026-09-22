# room-release-manager

## 목표
파티룸(`game-party-room-app`) 멀티 플랫폼 배포를 관리하는 macOS 메뉴바 앱.

## 지금 범위
- 저장 경로: AppPaths
- GUI: Window + Menubar
- CLI: room-release-manager
- **없음**:

## CLI
이 앱의 도메인 조작은 CLI가 문이다(App CLI First). 상태 파일 직접 수정·GUI 클릭 우회 금지.
```bash
room-release-manager capabilities
room-release-manager --help
```

## 상태
- 상태 루트: `AppPaths.stateDirectory()` → StateRootKit(`~/.room-release-manager/`).
- StateMirror: `~/.swift-app-state/room-release-manager.json`
- 헬스 펄스: `HealthPulse.publish(app:)` → `~/.swift-app-state/pulse/room-release-manager.pulse`
