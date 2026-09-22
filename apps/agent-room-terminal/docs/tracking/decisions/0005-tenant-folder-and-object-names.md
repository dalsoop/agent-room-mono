# 0005 — 방 폴더는 테넌트 정본 규약, 이름은 객체명

**상황**: 방 폴더 위치 후보가 둘이었다(`~/.agent-rooms/` 신설 vs 기존 SandboxKit 의 `~/.tenants/<슬러그>/` 정본). 함대 앱은 `SWIFT_APP_STATE_ROOT` 만 읽고, gujo 테넌트 정본은 `~/Library/Application Support/Gujo` 다.

**결정**: `~/.tenants/<슬러그>/rooms/…` 를 쓴다(샌드박스 승격 경로와 같은 정본). 새 env 키를 만들지 않고 `SWIFT_APP_STATE_ROOT` 에 테넌트 정책 stateRoot 를 넣는다. gujo 정본 경로는 바꾸지 않는다 — 이미 객체명(Gujo)으로 불리는 자리다. 테넌트·방·world 이름은 전부 객체 풀네임이다("일꾼 뽑는 자리" 비유: gujo = 운영하는 서비스명).

**대안**: (a) `~/.agent-rooms/` 신설 — 승격 경로를 따로 만들어야 한다. (b) 새 env 키 + gujo 정본 이전 — 함대 전체 수정.

**결과**: 테넌트 경로를 안 따르는 앱은 방에서 배제된다(준수 게이트). 미준수 앱을 쓰려면 그 앱을 고쳐야 한다.
