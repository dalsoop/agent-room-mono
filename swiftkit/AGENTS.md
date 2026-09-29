# swiftkit

이 저장소의 앱들이 공유하는 킷 라이브러리 패키지다. `Sources/` 아래 244개 폴더(라이브러리 타깃과 보조 C 타깃)가 있고, `Package.swift` 하나가 모든 제품·타깃·테스트 타깃을 선언한다. 플랫폼은 macOS 15·iOS 18, tools-version 6.1이다. 앱은 `.package(path: "../../swiftkit")`, 다른 킷 패키지는 `../swiftkit`으로 끌어온다.

## 범위

이 저장소에서 방 체제가 실제로 쓰는 킷은 다음과 같다. 나머지 킷(게임 엔진, 금전 원장, 볼트, 스토어 결제 등)은 swift-app-mono에서 함께 옮겨 온 것으로, 이 저장소의 앱은 쓰지 않는다.

| 킷 | 책임 | 의존 |
|---|---|---|
| `RoomKit` | 방 정의(`RoomSpec`, 예산 국면 판정 `BudgetJudgment`, 실행 정책, 계보), 벽 컴파일(`SeatbeltCompiler`, `PathPlanner`, `ExecRule`, `LaunchArgv`), 인지 원장(`RoomCognitiveLedger`, 델타·기계 측정·사전 계산·시냅스) | RoomPlacementKit · RoomSeatKit · StateRootKit · SkillRegistryKit · SessionKit · AppPathsKit · CommandKit |
| `RoomPlacementKit` | 방 폴더 경로(`RoomPaths`), 방 사건 로그(`RoomEventLog`, `events.jsonl`)와 상태 투영(`RoomStatusProjection`), 방 보관함 배치(`RoomVaultLayout`), 수명 상태·보관(`RoomLifecycleArchiver`), 스킬 승격 계약(`RoomPromotionGate`), 방 기억 색인 | StateRootKit · SkillRegistryKit · SessionKit |
| `RoomSeatKit` | 벽 값 타입(`RoomWalls`, `RoomWallPreset`, `NetworkWall`), 점유자 신원(`AgentOccupant`), 방 격리 문맥, 방 창 정책, 저장 공간 정리 | RoomPlacementKit · StateRootKit · SessionKit · FastDiskIOKit |
| `SandboxKit` | seatbelt 프로필·실행기·게이트·기록기·방 보관 | StateRootKit · CommandKit · swift-crypto |
| `StateRootKit` | 상태 루트 해석(`resolve`, 테넌트·테스트 격리), `~/.tenants` 규약, 고객용 방 저장소, 헬스 펄스 | 없음 |
| `CommandKit` | 프로세스 실행(`ProcessCommandRunner`, `SafeProcessRunner`, `CommandKitSync`, `ShellCommand`), 호스트 PATH(`HostPlatform.cliBinPath`), 종료 코드(`CLIExit`) | InteropKit · JSONLJournalKit · StateRootKit |
| `InteropKit` | CLI 봉투(`Envelope`), `capabilities` 모델 | PackageIdentityKit |
| `StateMirrorKit` | `~/.swift-app-state/<앱>.json` 게시와 읽기 | StateRootKit |
| `AppPathsKit` | 앱 sqlite 배치(`DurableAppLayout`) | StateRootKit · FastDiskIOKit · 시스템 sqlite3 |

## 범위 밖

- 앱 도메인 로직. 킷은 앱을 import하지 않는다.
- 무거운 원격 의존. 터미널 엔진은 `swiftkit-terminal`, Sparkle은 `swiftkit-sparkle`, 앱 스캐폴드와 트레잇은 `swiftkit-appscaffold`에 둔다. 이 패키지가 그 세 패키지를 의존하면 순환이 생긴다.
- `Derived/`와 `Project.swift`는 Tuist 생성물·매니페스트다. SwiftPM 빌드에 쓰이지 않으므로 손으로 고치지 않는다.

## 불변식

- 원격 패키지 의존은 swift-crypto와 swift-argument-parser 둘뿐이다. 새 원격 의존을 더하지 않는다.
- `StateRootKit.resolve`의 우선순위는 `SWIFT_APP_STATE_ROOT` → 테스트 러너(인자로 홈을 주지 않았을 때) → 테넌트 문맥(`ROOM_TENANT` → `AGENT_TENANT` → `TENANT_ID` → 문맥 파일) → 홈이다. 홈을 인자로 준 호출은 테스트 러너 감지보다 우선한다.
- `~/.tenants`는 홈 한 층이다. 상태 루트 경로에 `.tenants`가 있으면 그 층까지 올라간다(`tenantsRoot`). 겹친 `.tenants/.../.tenants`를 만들면 결함이다.
- 방 폴더 정본은 `RoomPaths.roomDirectory(tenant:roomID:)` = `<tenantsRoot>/<테넌트 슬러그>/rooms/<방id>`다. 방 id는 NFC로 맞춘다. `findRoomDirectory`는 정본 → 같은 이름 폴더 → 옛 2단 경로 순으로 찾는다.
- `RoomWallPreset`의 순서는 `readOnly` < `toolbelt` < `open`이고 toolbelt 상한은 6이다. 자식은 부모보다 넓을 수 없다.
- `SeatbeltCompiler.profile`은 `(allow default)`로 시작하고, 홈 쓰기 거부 → 방 폴더·임시 폴더 쓰기 허용 → `allowWrite` → `denyWrite`(셸 설정·`.gitconfig`·`.git/hooks` 필수 포함) → 읽기 규칙 순으로 쓴다. 이 순서는 뒤 규칙이 앞 규칙을 이긴다는 전제 위에 있다(홈 쓰기 거부 뒤에 방 폴더 허용이 온다). 필수 쓰기 거부를 허용 목록 앞으로 옮기지 않는다.
- 네트워크: `closed`는 `(deny network*)`와 프록시 env `http://127.0.0.1:9`, 프록시 포트가 있으면 그 포트만 outbound 허용, `open`은 규칙 없음과 빈 프록시 env.
- 상대 쓰기 경로는 `workdir` 기준으로 편다(없으면 방 폴더). `workdir`가 git 워크트리면 공용 git 디렉터리를 쓰기 허용에 더한다.
- `BudgetJudgment.phase`: 사용량을 모르면 시간 초과일 때만 `handoff-due`, 아니면 `unknown`. `used ≥ usable`은 `over`, `used ≥ handoffAt`은 `handoff-due`. 시간 초과는 `경과 ≥ 예상 × 3`.
- `SafeProcessRunner.run`은 던지지 않고 결과를 돌려준다. 호출부에 `do/catch`를 두지 않는다.

## 구현 패턴

- 킷 하나는 `Sources/<킷>/`와 `Tests/<킷>Tests/`, `Package.swift`의 `.library`·`.target`·`.testTarget` 세 줄로 이루어진다. 새 킷은 쓰는 앱이 하나 이상 있을 때만 더한다.
- 킷 설명서가 있는 경우 `Documentation/<킷>.md`에 둔다(`command-kit.md`, `state-mirror-kit.md`, `interop-kit.md` 등).
- 순수 계산(벽 컴파일, 경로 계획, 예산 판정)은 파일·프로세스 접근 없이 값만 받는 함수로 둔다. 파일 접근은 호출하는 앱이 한다.

## 테스트

- 바꾼 킷만 `swift test --filter <킷>Tests`로 돌린다. 필터 없는 전체 테스트는 모든 킷을 빌드한다.
- 방 킷을 바꾸면 `RoomKitTests`와, 그 킷을 쓰는 앱(`apps/agent-room-terminal`, `apps/agent-room-monitor`)의 빌드·테스트까지 돌린다.
- 테스트는 `SWIFT_APP_STATE_ROOT` 또는 테스트 러너 격리 루트(`$TMPDIR/swift-app-state-root-tests`)를 쓴다. 실제 `~/.tenants`에 쓰면 결함이다.
- 이 패키지는 swift-app-mono의 같은 이름 패키지와 갈라져 있다. 킷을 고치기 전에 어느 쪽이 정본인지 확인한다.
