# AgentRoomTerminalCore

## 범위

방 폴더 조립(Room), 데몬 프로토콜 타입·프레이밍·클라이언트·세션 인가 규칙(Daemon), 세션 모델·링 버퍼(Terminal), 원장 직렬 큐(Ledger), 예산·사용량·핸드오프·도구 선택(Budget), 습관·시뮬레이션·승격(Habit), 층 배치·LOD 순수 계산(Canvas), 튜닝값(Tuning), StateMirror 게시. GUI·CLI·데몬이 전부 이 모듈의 진입점을 부른다.

## 범위 밖

PTY 생성과 터미널 파싱(데몬 타깃), 화면 그리기(GUI 타깃), 서브커맨드 파싱·출력 봉투(CLI 타깃), 다른 앱의 상태 파일(원장·정책·위키 — CLI 호출만).

## 불변식

- AppKit·SwiftTerm 을 import 하지 않는다.
- 모든 외부 CLI 호출은 프로토콜(`LedgerCommandRunning`·`ComplianceChecking`·`WikiPublishing`·`CapabilityLookup`·`ExecRunning`·`HandoffLedgerPort`) 뒤에 있고, 테스트는 픽스처 구현을 쓴다.
- 원장 쓰기는 `LedgerQueue.submit(_:by:)` 하나만 지난다. 요청자 권한이 대상 방·그 자식이 아니면 큐에 넣기 전에 `foreignRoom` 으로 거부한다.
- `RoomFolder.assemble` 은 멱등이다. 자식 `bin` ⊆ 부모 `bin`, 자식 프리셋 ≤ 부모 프리셋, 자식 writePaths ⊆ 부모 writePaths 가 아니면 throw.
- `Budget.compute` 는 `used` 가 unknown 이면 토큰 축을 판단하지 않고, 결과 `unknown` 이면 핸드오프를 제안하지 않는다.
- `Simulator` 는 `CapabilityLookup` 이 `dryRun: true` 를 돌려준 명령만 `ExecRunning` 으로 실행한다. 그 밖은 기록 대조만.
- 경로는 AppPaths/StateRootKit 으로만 조립한다.

## 패턴

- 파일 시스템 조작은 `FileManager` 직접이되 경로는 AppPaths 에서 받는다. 도구별 규격표(`ToolBudgetSpec`)는 값 타입 상수다.
- 외부 CLI 의 stdout 은 첫 `{`/`[` 부터 JSON 파싱한다(설치본 경고 접두).
- 오류는 도메인 enum(`RoomAssemblyError`·`LedgerError`·`SimulationError` 등)으로 throw 한다. `try?` 로 버리지 않는다.

## 테스트

멱등 조립(두 번 조립 = 같은 트리), 프리셋 3종 bin, 미준수 배제, 자식 상속 위반, env 키 집합 일치, 큐 직렬성(동시 100건 순서·동시 실행 0), 타 방 거부, 예산 4종 픽스처·토큰/시간 handoff-due·unknown, predecessor 사슬, dry-run 없는 명령 미실행(스파이), 이탈 노트 없는 이탈 실패, handover 전이, 층 배치 시간·겹침, LOD 상한.
