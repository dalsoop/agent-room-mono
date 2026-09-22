# Changelog

All notable changes to `agent-room-terminal-swift` will be documented in this file.

## [1.0.104] - 2026-09-21

### Added
- RoomAppBorrow membership lock (Safari borrow/expiry, closed-room freeze).

## [1.0.103] - 2026-09-19
### Fixed
- Handle pipe close errors in herdr launch backend.

## [1.0.102] - 2026-09-19
### Fixed
- Reconcile pure pipeline arguments and flatten verdict/session branch logic.
- Bind CLI/UI surface parity suppression ticket to daemon core.

## [1.0.101] - 2026-09-19
### Changed
- Align AppPaths.stateDirectory to use StateRootKit.ensureCustomerRoomStorage for customer environments.

## [1.0.100] - 2026-09-17
### Changed
- Eliminate literal "-c" flag in ExecRunner, SRTLaunch, and RoomCommandCheck.

## [1.0.99] - 2026-09-17
### Fixed
- `RoomOps.remoteRunner`를 `OSAllocatedUnfairLock` 연산 프로퍼티로 원자화하여 동시성 Data Race 방어.

## [1.0.98] - 2026-09-16

### Changed
- Standardize AppPathsKit, eliminate raw shell execution, and unify CommandKit and ISO8601DateCodecKit.

## [1.0.97] - 2026-09-13

### Added
- 인지 원장 실측 엔진 결선: `precompute`, `delta`, `synapses` CLI 명령 추가.
- `close` 명령 시 기계적 `RoomMechanicalProbe` 및 `driftScore` 자동 산출, 가설 기각 시 `invalidates` 시냅스 자동 체결.

## [1.0.96] - 2026-09-13

### Changed
- `StateMirrorAdoption.publish(_ state: State)` 추가로 상태 미러링 생명주기 동기화 및 필드 유실 방지.

## [1.0.95] - 2026-09-13
### Added
- `ProfileThenLock` 엔진 및 `TraceLogParser`: 방 실행 프로파일 기반 방벽 자동 도출 및 잠금 기능 추가
- `RoomCheckpointManager` 및 `RoomGuardedRunner`: 세이프 가드 실행 롤백 및 체크포인트 보존
- `SourceHashGate`: 방 조립 시 소스 무결성 검증 게이트 결속

## [1.0.93] - 2026-09-12
### Fixed
- `RoomListView` 메인스레드 동기 파일 I/O 전면 제거 및 비동기 캐시 프리로드 전환 (스크롤 프리징 해소)
- `RoomSeatTabDetailView` 하드코딩 더미 목업 및 가짜 진행도 전면 척결 (정규 Empty State 적용)
- 자식 방 `tenantID` 보존 및 물리 디스크 경로(`.tenants/<slug>/rooms/...`) 기반 부모 테넌트 역추적 복원
- macOS APFS(NFD) 한글 방 폴더명 및 검색 쿼리 완성형(NFC) 유니코드 정규화
- 테넌트 아코디언 헤더 및 수평 필터 칩 바 탑재, 캔버스/퍼스펙티브 뷰포트 반응형 확장

## [1.0.92] - 2026-09-11
### Added
- 관점 뷰(Perspective View v12.1) 도입: 4단 동심원 레이더 그래프(RadialRadarCanvasView) 및 시간축 트랙·스크러버(TimelineTrackBoardView) 연동.

## [1.0.91] - 2026-09-10
### Added
- 우측 인스펙터 5대 탭 체제([방] [좌석] [권한] [컨텍스트] [이벤트]) 및 정본 시안(InspectorSeatHandoff.dc.html) 1:1 이식.
- 3열 빠른 실행 액션 그리드(터미널 열기, 넘기기, 판정 실행 등) 및 캔버스 카드 우클릭 컨텍스트 메뉴(Actions.dc.html).
- 기본 뷰 모드를 캔버스로 전환 및 첫 번째 활성 방 자동 선택 유지.

## [1.0.90] - 2026-09-10
### Added
- 물리적 좌석 상태(재실/공석 책상/방 밖 세션) 배지 시각화 및 좌석 사슬 UI 리팩토링.

## [1.0.89] - 2026-09-10
### Added
- 방 상세 좌석 사슬 카드, room-graph.json 파일 감시.

## [1.0.88] - 2026-09-10
### Added
- Resolve claude/codex/grok/agy transcript paths from measured rules, preferring seat `transcript.path`.
- `open --attach-session` registers room walls and transcripts without creating a PTY (`enforcement: walls-registered-only`).
- Room detail "벽 붙이기(attach)" button calls the same attach core.

## [1.0.87] - 2026-09-09
### Added
- Elevate room handoff and bottle swap flow to smoke test.

## [1.0.86] - 2026-09-09
### Added
- Canvas tenant filter, pan-to-fit, and hide dismantled rooms by default.
