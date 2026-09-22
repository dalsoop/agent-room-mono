# Changelog

All notable changes to `agent-room-monitor-swift` will be documented in this file.

## [1.0.29] - 2026-09-19
### Changed
- Customer-grade single room local storage adoption via StateRootKit.ensureCustomerRoomStorage(slug:).

## [1.0.28] - 2026-09-16

### Changed
- Standardize AppPathsKit, eliminate raw shell execution, and unify CommandKit and ISO8601DateCodecKit.

## [1.0.27] - 2026-09-13

### Changed
- `StateMirrorAdoption.publish(_ state: State)` 추가로 상태 미러링 생명주기 동기화 및 필드 유실 방지.

## [1.0.26] - 2026-09-11

### Fixed
- **SnapshotBuilder**: 배치도 내 실행 중인 방(`occupied`/`executing`/`active`)이 감지되면 활성 배치도로 승격 분류하여 워커 좌석 투영 정합성 확보.
- **AgentRoomMonitorCLI open**: `/Applications/AgentRoomMonitor.app` 실존 경로 및 `-a AgentRoomMonitor` 대소문자 매핑으로 GUI 앱 실행 실패 해소.

## [1.0.25] - 2026-09-11

### Added
- **FloorBuildingHierarchyBar**: 테넌트 건물 계층(Building Hierarchy) 가로 스택 바 추가로 건물별 방 수, 활성 세션 수, 격리 리스크를 한눈에 조망 및 원클릭 건물 필터링 연동.
- **BoardModel**: 테넌트 건물 계층 집계 요약(`buildingSummaries`) 제공.
- **CLIOwnerBridge**: `agent-work-todo placement list --all` 연동으로 전체 55개 배치도 및 117개 방 실데이터 100% 디지털 트윈 미러링 완결.
- **CLIJSON**: 스트림 앞뒤 경고 배너/공백 격리(`cleanJSONData`) 및 `ShipJobDTO` 타임스탬프 유연 디코딩 도입.
- **SnapshotBuilder**: 테넌트 빌딩 자식 노드에 `lobbyRoom` 계층 포괄 및 `isLobby`/`isArchive` 상태 매핑 확장.

## [1.0.24] - 2026-09-11

### Added
- **agent-surface**: CLI 에 에이전트 레일(`agent`·`skill`·`chat`)을 심고, 앱에 쌓인 에이전트·스킬 시드를 레포에 남긴다. 도메인 `status` 는 레일이 가로채지 않는다.

## [1.0.23] - 2026-09-11
### Fixed
- VNode `find(_ targetID: String)` 중복 선언(invalid redeclaration) 제거.

## [1.0.22] - 2026-09-11
### Fixed
- VWorld 및 VNode에 `find(_ targetID: String)` 헬퍼 구현으로 MemorySearchPopover에서 방 선택 시 빌드 실패 교정.

## [1.0.21] - 2026-09-10
### Added
- MemorySearchPopover GUI 컴포넌트 추가 및 메인 상단 크롬에 테넌트 교차 메모리 검색 팝오버 배선.
- DetailPanelVaultSection에 Auto-bumped 영수증 뱃지 및 스킬 승격 시 autoBump 옵션 연동.

## [1.0.20] - 2026-09-10
### Added
- RoomMutationService 및 CLI `mutate promote-skill --auto-bump` 자동 마이너 버전 승격 지원.
- RoomMutationService 및 CLI `mutate search-memory --query` 테넌트 교차 메모리 검색 추가.

## [1.0.19] - 2026-09-10
### Added
- FloorGridWidgets: 에이전트 Pawn 뱃지, 10만 토큰 상한 링, 방OS 트윈 상태 점, 테넌트 빌딩 계층 뱃지 및 상단 거시 HUD 바 추가 (위키 정본 913d45ec 요구사항 v4 32항 연동).
- FloorGridView 격리 표에 실데이터 인코딩된 시각화 위젯 연동 및 클로저/불린 린트 클린업.

## [1.0.18] - 2026-09-10
### Added
- RoomMutationService 및 CLI `mutate seal`, `mutate archive`, `mutate promote-skill` 명령 연동.
- DetailPanelVaultSection 봉인, 아카이브, 승격 액션 버튼 및 다건 영수증 카운트 배지 추가.

## [1.0.17] - 2026-09-10
### Added
- DetailPanelView 룸 볼트 격리 저장소(curated 산출물, 로컬 스킬, 승격 영수증, 생명주기) 표시 기능 추가.

## [1.0.16] - 2026-09-09
### Changed
- CLI `version` / `--version` / `capabilities --json` 마케팅 스탬프를 호스트 Info.plist `CFBundleShortVersionString`과 맞춘다.
