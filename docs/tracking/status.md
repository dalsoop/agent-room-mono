# 현황

기준일 2026-09-30, 기준 커밋 `446385f`(origin/main). 이 저장소는 2026-09-23 첫 커밋(`fa357fc`)으로 swift-app-mono의 방 관련 앱 넷과 공용 킷 넷을 옮겨 와 만들어졌고, 그 뒤 커밋 여섯 개는 README 보강, 엔드포인트 폴백 주소 교체, `gujo-product.json` 상품 번호 결속이다.

## 만든 것과 검증 상태

| 부분 | 상태 | 근거(2026-09-30, 이 Mac, `build-queue-manager`로 실행) |
|---|---|---|
| `apps/agent-room-monitor` | 만듦·빌드 통과·테스트 통과 | `swift build`(GUI·CLI·Core 전체) 종료 0. `swift test` XCTest 30건 통과(RoomBoardSurfaceTests·SmokeTests·ViewSpecStoreTests) |
| `apps/agent-room-terminal` | 만듦·빌드 실패 | `swift build` 종료 1. 킷과 Core·GUI 타깃에서는 오류가 나지 않았고, 데몬 타깃의 `ExecRunner.swift`·`HerdrLaunchBackend.swift`·`DaemonServer+LaunchExec.swift`에서 컴파일 오류가 났다. 테스트 타깃 셋(Core·Daemon·Smoke, Swift 소스 79개)은 빌드 실패로 돌리지 못했다. CLI 타깃은 컴파일 단계에 이르지 못했는데, `AgentRoomTerminalCLI/CognitiveCommands.swift`에도 인자 목록의 쉼표가 어긋난 `SafeProcessRunner.run(…)` 호출이 있다 |
| `apps/agent-room-isolator` | 만듦·패키지 해석 실패 | `swift build` 종료 1: `../../Common/System`이 없다. 해석을 통과해도 `AgentRoomWorktreeCLI/main.swift`의 `open` 분기에 짝 없는 `} catch {`가 있다. XCTest 소스 한 개(SmokeTests, 테스트 함수 14개)는 돌리지 못했다 |
| `apps/room-release-manager` | 만듦·빌드 실패 | `swift build` 종료 1. `PartyRoomReleaseManagerCLI/main.swift`의 서로 다른 위치 5곳에서 컴파일 오류(`open` 분기의 짝 없는 `} catch {`) |
| `swiftkit-terminal` | 만듦·테스트 통과 | `swift test` XCTest 13건 통과(TerminalEngineKitTests 12, TerminalEngineGhosttyTests 1) |
| `swiftkit-appscaffold` | 만듦·테스트 통과 | `swift test` Swift Testing 74건(10개 묶음) 통과 |
| `swiftkit-sparkle` | 만듦·테스트 통과 | `swift test` Swift Testing 3건 통과 |
| `swiftkit`(244개 킷) | 만듦·이 저장소에서 미검증 | 전체 테스트는 모든 킷을 빌드해야 해서 돌리지 않았다. 방 관련 킷(RoomKit·RoomPlacementKit·RoomSeatKit·SandboxKit·StateRootKit·CommandKit)은 관측판·터미널 킷 빌드의 의존으로 컴파일은 됐다(관측판 빌드 성공, 터미널 빌드는 킷 단계를 지나 앱 데몬 타깃에서 실패) |
| 실제 방 열기·벽 확인·자격증명 삭제 | 이 저장소 판에서 미검증 | 터미널이 빌드되지 않아 런타임 확인을 하지 못했다 |
| CI | 없음 | 저장소에 CI 설정과 git 훅이 없다 |

## 남은 것 (우선순위 순)

1. `agent-room-terminal`·`room-release-manager`·`agent-room-isolator` CLI의 `SafeProcessRunner` 기계 치환 잔해를 고쳐 컴파일을 되살린다. 같은 파일의 swift-app-mono 판이 고친 모양(`if !safeResult.ok { … }`)을 보여 준다.
2. `agent-room-isolator`의 `../../Common/{System,CLI,UI}` 의존을 이 저장소 안의 킷으로 바꾸거나 지운다.
3. 세 앱을 빌드한 뒤 각 패키지의 `swift test`를 돌려 기준선을 만든다.
4. 방 하나를 실제로 열어 벽 확인 순서(PATH, 절대경로 거부, 리다이렉션 거부, 네트워크 차단, 닫은 뒤 자격증명 사본 삭제)를 실측한다.
5. 앱 식별자 불일치(격리기 `agent-room-worktree`, 파티룸 `party-room-release-manager`·번들 id)와 버전 불일치를 정리한다.
6. `apps/agent-room-terminal`의 앱 전용 문서 묶음을 이 저장소 코드에 맞게 고친다(원장 CLI 호출, 방 폴더 경로, 튜닝 키 수 등).
7. swift-app-mono에 있는 같은 앱·킷 사본과 이 저장소 중 어느 쪽이 정본인지 정하고, 정본이 아닌 쪽을 동기화하거나 퇴역시킨다.

## 막힌 것

- 7번은 저장소 주인의 결정이 필요하다.
