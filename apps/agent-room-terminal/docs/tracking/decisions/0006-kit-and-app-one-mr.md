# 0006 — 새 kit 과 새 앱 골격은 한 MR, 이식 코드는 규칙에 맞게 교정

**상황**: SandboxKit 은 미병합 브랜치의 코드를 "그대로 이식" 하기로 했는데, 저장소 커밋 게이트가 그 코드의 기존 부채(상태 경로 하드코딩·오류 삼킴·Process 직접 사용)를 실패로 쳤다. 또 새 swiftkit 라이브러리는 쓰는 앱이 있어야 게이트를 통과하는데 쓰는 앱(이 앱)이 같은 바퀴에 태어난다.

**결정**: 이식 코드를 저장소 규칙(StateRootKit 경로·CommandKit·오류 전파·실제 Sendable)에 맞게 고치되 동작과 테스트(보안 exploit 테스트 포함)는 유지한다. SandboxKit 과 이 앱의 골격(SandboxKit 채택)은 한 MR 로 낸다 — 앱별 MR 분리 규칙의 예외 한 건.

**대안**: (a) 원본 브랜치 병합을 기다림 — 이 바퀴 전체가 멈춘다. (b) kit 을 허용 목록에 임시 등록 — 그 파일이 "신규 kit 은 넣지 않는다" 고 명시한다.

**결과**: 원본 브랜치와 SandboxKit 코드가 갈린다. 원본 브랜치가 병합될 때 seat-manager 의 room 명령·RoomOps·RemoteRoomRunner·SandboxKit 의존을 빼야 한다.
