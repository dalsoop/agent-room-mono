# 현황

## 만든 것 (첫 바퀴, 2026-09-03)

| 부분 | 상태 | 근거 |
|---|---|---|
| 방 폴더 조립(멱등·프리셋 bin·env·준수 게이트·자식 상속·RoomOps 이관) | 만듦·테스트 통과 | Core/Room 테스트 16건 |
| 실행 데몬(소켓·PTY·zsh -r·seatbelt·링 버퍼·유휴 종료·attach 스트림·세션 인가·오류 보고) | 만듦·테스트 통과·실측 | 데몬 테스트, 실제 방 열어 벽 4종 확인, 유휴 60초 종료 확인 |
| 원장 결속 단일 큐(occupy·handover·tick·spawn-room, 타 방 거부) | 만듦·테스트 통과 | Core/Ledger 테스트 11건 |
| 예산·사용량 원장·핸드오프 사슬·도구 선택 | 만듦·테스트 통과 | Core/Budget 테스트 58건 (Antigravity 사용량은 항상 unknown) |
| 습관 저장소·시뮬레이션(dry-run 계약만 실행)·자동 승격 | 만듦·테스트 통과 | Core/Habit 테스트 47건 |
| 트리 캔버스(층 배치·LOD·SwiftTerm 오버레이·상세 패널·튜닝 설정) | 만듦·테스트 통과·실행 확인 | 50방 픽스처, AX 노드 50개, 프레임 p95 8ms |
| CLI 배선·capabilities·튜닝 저장소 | 만듦·테스트 통과·실측 | GUI 튜닝은 PersistentTuning 으로 같은 tuning.json |
| StateMirror 앱 필드·성능 강등·화면 액션 코어 결속 | 만듦·테스트 통과 | 화면은 RoomTreeSource 로 실제 방 폴더를 읽는다(2026-09-03 결속) |
| 기존 앱: 원장 헌법 확장(agent-work-todo) | 병합·테스트 166건 통과 | |
| 기존 앱: SandboxKit·RoomWallKit(swiftkit) | 병합·테스트 통과 | 이식 코드는 저장소 규칙에 맞게 교정 |
| 기존 앱: 테넌트 준수 판정·world ensure(agent-tenant-isolation-manager) | 병합·테스트 128건 통과·실측 | tenant-gujo world 등록됨 |
| 기존 앱: 위키 테넌트 층(agent-wiki-kit·global·local·ui) | 병합·테스트 통과 | 공용 로직은 kit 에 |
| 기존 앱: 방 벽 훅 규칙(agent-guardrail-manager) | 병합·테스트 통과 | 실제 settings 에는 미적용 |
| tenant:gujo 상주 설계도 4장 | 원장 등록·방 4개 실제로 열어 실측 | 벽 확인(kubectl 없음·절대경로 거부·미준수 배제), 화면에 실제 트리 |

## 남은 것 (이 바퀴)

1. 앱별 MR 분리(swiftkit+새 앱 · agent-work-todo · agent-tenant-isolation-manager · agent-wiki-kit · agent-wiki-global · agent-wiki-local · agent-wiki-ui · agent-guardrail-manager).
2. 에이전트 한 명을 방에 앉혀 실제 과제를 판정(verdict)까지 끝내는 첫 사례(아직 0건). 스모크 테스트 타깃은 핸드오프→후임→시뮬레이션까지 실제로 돈다.

## 2차 물결 (2026-09-03 저녁, 워커 6명 병렬 · 커밋 3ed67f0a3c 까지)

| 묶음 | 내용 | 검증 |
|---|---|---|
| W1 CLI | `open` 이 seatbelt 프로필을 데몬에 실음(1차 검토 반려 원인), 멱등(같은 방 세션 재사용, occupy 실패 시 세션 닫음), verdict 실행 가능성 경고, `Process` → CommandKit | 실측: seatbelt true · reused true · `verdict command excluded: gujo-catalog-manager` |
| W2 원장 | `placement vacate`, `instantiate-due` 가 열린 설계도 건너뜀, verdict-toolbelt 검증, `room enter --json` env, `occupy --session` | agent-work-todo 173건 |
| W3 예산·데몬 | 전사(JSONL) 파싱 사용량 어댑터(claude usage·codex last_token_usage·증분 커서), 세션 표 `sessions.json` 영속화·복구 | 141건 |
| W4 핸드오프 | 빈병에 pitfalls·decisions·remaining, escalated→failed+note, 실행 스모크 테스트 타깃(실제로 돎) | 140건 |
| W5 화면 | 실제 방 메뉴 결속, 배제 사유(백그라운드 조회), "방 세우기" 시트 | 빌드·GUISurfaceTests 9건(병합본에서) |
| W6 kit·정책 | `StateRootKit.tenantsRoot` 정본, exec 판정 4종(redirect·quarantine), 설치본 stale 표시 | kit 15 + 앱 145 |

실측(새 데몬): 절대경로·`sh -c`·`rm -rf` 거부, `ls bin` 통과, 방 env 루트 `~/.tenants/gujo`, 예산은 전사 등록 전이라 unknown.

## 실측 결함 수리 (2026-09-03, 커밋 205bac1576 · a757b16827)

단위 테스트 전부 통과 상태에서 gujo 방 4개를 실제로 열자 8건이 연달아 나왔다. 전부 수리·테스트 추가.

| 결함 | 수리 |
|---|---|
| 원장 CLI 출력 64KB 초과 시 파이프 교착 | 종료 대기 전에 백그라운드 drain |
| PATH 호출 시 데몬 실행 파일 못 찾음 | 실경로·PATH 탐색(DaemonExecutable) |
| 방 폴더 `.tenants/personal/.tenants/gujo` 겹침 | `.tenants` 홈 한 층 규약, RoomPaths 단일화 |
| 배치도 방에 설계도 본문 없음 | `room list` 로 slug 병합 |
| 착석 신원 `@host` 고정으로 두 번째 방 거부 | 실제 호스트 라벨 + 원장 `--session` |
| 방 env 상태 루트가 지휘실 테넌트 | 방의 테넌트 루트(tenantStateRoot) |
| exec 가 절대경로·셸 우회 실행 | ExecPolicy(제한 셸과 같은 선) |
| verdict `{command:{_0:…}}` 미해석 | 해석 |

## 남은 것 (다음 바퀴 이후)

- 원격 호스트 방(이관된 RemoteRoomRunner 활성화, 트리에 호스트 축).
- Gemini CLI·Kiro 어댑터. Antigravity 사용량 측정.
- 원장에 빈병 digest 전용 쓰기 명령(지금은 방 `handoff/` 파일이 정본이고 원장에는 `occupy --successor` 만 간다).
- 방 폴더 크기·보관 정책 GUI. 화면에서 설계도 편집.
- 설치(ship)와 `agent-surface-reach matrix --slug agent-room-terminal --strict`.

## 막힌 것

없음.
