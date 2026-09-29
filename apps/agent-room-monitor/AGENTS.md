# agent-room-monitor

방·자리·스킬·세션·앱 빌드·설비·호스트 상태를 다른 앱의 CLI 출력으로 모아 한 층 평면도(FloorGrid)와 HUD로 보여 주고, 방 조작 버튼을 소유 CLI 호출로 옮기는 macOS 창 앱이다. PATH CLI는 `agent-room-monitor`, GUI 제품은 `AgentRoomMonitor`, 번들 id는 `net.ranode.agent-room-monitor`다.

## 범위

- `AgentRoomMonitorCore`: 스냅샷 조립(`SnapshotBuilder`와 `+Flows`·`+Layout`·`+WorkRooms`·`+Zones`), 소유 CLI 브리지(`CLIOwnerBridge`, `OwnerDTOs`), 방 조작(`RoomMutationService`), handle 검사(`RoomHandleGate`), 격리 위험 판정(`IsolationRisk`), 스냅샷 보관과 비교(`SnapshotArchive`, `SnapshotDiff`), 훅 트레이스(`TraceStore`), 뷰 정의(`ViewSpec`), AX 요약(`OccupancyAX`), 상태 경로(`AppPaths`), StateMirror 게시.
- `AgentRoomMonitor`(GUI): `MainView` = 상단 크롬(테넌트 메뉴·시점 도크·새로 고침·기억 검색·새 방) + `FloorGridView` 한 장 + 상세 패널.
- `AgentRoomMonitorCLI`: 명령 분기와 JSON 출력. `agent`·`skill`·`chat`은 AgentCLIKit에 넘긴다.

## 범위 밖

- 방 폴더 조립, PTY, 벽 계산(방 터미널 앱의 일이다).
- 원장·자리·세션·볼트의 정본. 이 앱은 그것들을 CLI로 읽기만 하고, 조작도 소유 CLI(`agent-work-todo`, `agent-handoff`)에 맡긴다. 예외는 방 보관함 조작(`seal`·`archive`·`promote-skill`·`search-memory`)으로, RoomPlacementKit(`RoomLifecycleArchiver`, `RoomPromotionGate`, `RoomMemoryIndexer`)을 직접 쓴다.
- `Sources/AgentRoomMonitor/HexBoard.swift`는 `Package.swift`에서 빌드 제외돼 있다. 고쳐도 앱에 반영되지 않는다.

## 불변식

- 스냅샷의 공급원은 `OwnerFetching` 하나다. 파일 시스템에서 다른 앱의 상태를 직접 읽는 공급원을 더하지 않는다.
- 공급 CLI 하나가 실패해도 `build()`는 끝까지 스냅샷을 만든다. 실패는 그 영역의 빈 값과 뿌리 노드 `health.notes`의 한 줄로만 나타난다(테스트 `testBuildSurvivesMissingSources`).
- 공급원에 없는 값을 지어내지 않는다. 세션 카드·외부 네트워크·Datadog 층·점유 에이전트는 CLI가 준 것만 그린다(테스트 `…WithoutInventing…` 묶음).
- 방의 테넌트는 `placement.tenantID`다. 자리(seat)의 테넌트로 방의 테넌트를 바꾸지 않는다. 테넌트 목록에 없어도 배치·자리에 나오는 테넌트 id는 목록에 더한다.
- 운영 소스에 호스트 픽스처(고정 호스트 이름·사용자 경로)를 넣지 않는다(테스트 `testProductionSourcesForbidHostFixtures`).
- `MainView`는 평면도 한 장만 그린다(테스트 `testMainViewIsSingleFloorGrid`). 탭이나 두 번째 보드를 더하지 않는다.
- `spawn-room`은 `RoomHandleGate`를 통과한 handle만 원장에 보낸다. 빈 값, 40자 초과, `/`·`\` 포함, `tenant:` 접두는 거부한다.
- 조작 시간 제한: `tick` 180초, `spawn-room` 120초, 나머지 30초.
- 상태 경로는 `AppPaths`(StateRootKit)에서만 나온다. `SWIFT_APP_STATE_ROOT`가 없으면 `~/Library/Application Support/net.ranode.shared/rooms/room-default/agent-room-monitor/`, 있으면 `<루트>/.agent-room-monitor/`다. 그 아래 `trace/`, `snapshots/`, `views/`.

## 구현 패턴

- 새 공급원: `OwnerFetching`에 메서드를 더하고, `CLIOwnerBridge`에서 `HostPlatform.cliBinPath("<cli>")`로 경로를 잡아 `run`/`decodeList`로 부른다. 출력은 `CLIJSON.payload`로 경고 배너를 벗기고 디코드한다. 실패는 `BridgeResult(value: <빈 값>, note: "<cli> … 실패: …")`로 돌려준다.
- 새 조작: `RoomMutation`에 case를 더하고 `argv(_:)`에서 소유 CLI 인자 배열을 만든다. 파일을 직접 쓰는 조작은 `perform`의 앞부분에서 따로 처리한다. CLI의 `mutate` 분기와 GUI 상세 패널 버튼을 함께 더한다.
- 외부 명령은 `CommandRunning` 주입(`ProcessCommandRunner`)으로만 부른다. CLI의 `open` 분기만 `Process()`를 직접 쓰고 있다(고쳐야 할 기존 위반).
- 문안은 `L10n`/`CLILocalization` 키로 낸다.

## 테스트

- `swift test`는 XCTest 30건이다. 공급원은 `OwnerFetching`/`CommandRunning` 가짜로 주입하고, 실제 CLI·실제 원장을 부르지 않는다.
- 새 공급원·조작마다 확인할 것: CLI가 없을 때 스냅샷이 계속 만들어지는지, 출력 앞에 경고 배너가 붙어도 파싱되는지, 조작의 argv가 정확한지(`testMutationServiceCallsOwnerCLI` 꼴), 테넌트가 섞이지 않는지(`testTenantBuildingsKeepSilneobalOutOfPersonal` 꼴).
- GUI 변경은 빌드와 소스 계약 테스트(`RoomBoardSurfaceTests`)로 확인한다.
