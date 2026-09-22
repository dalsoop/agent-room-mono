# 규칙

## 이름

테넌트·방·위키 world 는 객체의 풀네임이다. 테넌트 `gujo` 는 서비스 Gujo 를 뜻하고, 방 slug 는 `<객체>-<역할>`(`gujo-seller-operations`), world 는 `tenant-<객체>`. slug 는 `[a-z0-9]+(-[a-z0-9]+)*` 만 허용하고 위반은 조립 실패다. 은유·약어로 된 이름을 새로 만들지 않는다.

## 방 (Room)

- 방은 원장의 배치된 방 하나에 대응한다. 식별자는 원장 UUID, 표시명은 slug.
- 폴더 `~/.tenants/<테넌트슬러그>/rooms/<배치도id>/<방slug>/`. 앱 상태 정본은 이것과 별개인 테넌트 정책의 `stateRoot`(gujo 는 `~/Library/Application Support/Gujo`, 새 테넌트는 `~/.tenants/<슬러그>/state`).
- 조립은 멱등이다: 같은 원장 상태에서 두 번 조립하면 같은 파일이 나와야 하고, 다른 결과가 나오면 결함이다.
- 폴더 구성: `ROOM.json`(읽기 전용, 설계도 스냅샷·상태·예산·excludedTools·preset) · `ROOM.md`(조립문) · `bin/` · `env` · `work/` · `state/`(term.log·usage.jsonl·notes/) · `children/` · `handoff/` · `habits/`.
- 방을 닫으면 프로세스는 없고 폴더만 남는다. 폴더는 7일 보관 뒤 소각된다.

## 벽 프리셋

| 프리셋 | bin/ | 셸 | 샌드박스 | 여는 조건 |
|---|---|---|---|---|
| readOnly | 기본 셸 폴더만 | zsh -r | 켬 | 없음 |
| toolbelt(기본) | 기본 셸 폴더 + 설계도 toolbelt(6개 이하) | zsh -r | 켬 | 없음 |
| open | 비움(PATH 전체를 env 로) | zsh | 켬(파일 쓰기만 제한) | 지휘실 세션 또는 사람이 `--preset open` 을 명시. 화면에 "개방" |

- 기본 셸 폴더 `~/.tenants/_base-bin/` 은 `ls cat head tail sed grep find wc git` 아홉 개와 `agent-room-terminal` 자신, 열 개 심링크뿐이다. `python3 sh bash env osascript` 는 넣지 않는다.
- toolbelt 6개 상한은 toolbelt 프리셋에만 적용된다. open 프리셋에는 적용되지 않는다.
- 자식 프리셋은 부모보다 넓을 수 없다(readOnly < toolbelt < open). open 부모의 자식은 open 가능, toolbelt 부모의 자식은 toolbelt·readOnly 만. 위반은 조립 실패다.

## 테넌트 준수

toolbelt 의 앱은 `agent-tenant-isolation-manager check <cli> --json` 이 compliant 인 것만 `bin/` 에 들어간다. 준수 = capabilities 가 `stateRoot.env == "SWIFT_APP_STATE_ROOT"` 를 선언하거나, 그 env 를 임시 폴더로 준 `status --json` 실행이 그 폴더 아래에 파일을 만드는 것. 미준수 앱은 어떤 프리셋에서도 심링크되지 않고 `excludedTools` 에 남으며 화면 칩 "미준수 N" 으로 보인다. 예외는 없다.

## 세션과 자식 방 — 단방향 결속

- 자식 방은 부모 터미널에서만 생기고(`open <자식>`), 방 자체는 `agent-room-monitor mutate spawn-room` 이 원장에 만든다. 자식 폴더는 부모 `children/` 아래.
- 자식 `bin/` ⊆ 부모 `bin/`, 자식 walls ⊆ 부모 walls, 자식 프리셋 ≤ 부모 프리셋.
- 자식이 부모에게 돌려줄 수 있는 것은 원장 상태 전이(성공·blocked)와 빈병 파일뿐이다. 프로세스 간 파이프·소켓·공유 파일 통로는 없다. 부모는 `children/*/handoff/` 와 `snapshot` 을 읽기 전용으로 본다.
- 자식은 부모·형제 방을 조작할 수 없다. 자기 방 id 와 자기가 연 자식 방 id 이외의 요청은 거부된다.
- 같은 프로세스 안의 서브에이전트 도구는 방 안에서 쓰지 않는다. 훅 `check --tool Agent` 는 방 안이면 항상 거부한다.
- 이미 돌던 세션이 훅만으로 방에 앉으면 원장 `wallMode = hookOnly` 로 기록되고 화면에 "약한 벽" 이 붙는다. Codex·Antigravity 는 훅 표면이 없어 세 겹 벽만으로 서고 `full` 로 기록된다.

## 예산과 핸드오프

도구별 실효 입력(usable): Claude Code `1,000,000×0.835 − initialInput`, Codex `272,000 − 13,000 − initialInput`, Grok `500,000×0.8 − initialInput`, Antigravity `200,000×0.8 − initialInput`. `handoffAt = usable × 0.8`(튜닝값). `initialInput` 은 방을 열 때 조립문·ROOM.md·주입 문서 토큰을 더한 값.

- 사용량은 로컬 세션 기록만 읽는다(네트워크·API 키 없음). 읽지 못하면 `unknown` 이며 추정하지 않는다. Antigravity 는 항상 unknown.
- `state` ∈ ok · handoff-due · over · unknown. handoff-due = `used ≥ handoffAt` **또는** `elapsedMinutes ≥ estimatedWorkMinutes × 3` 중 먼저. 토큰이 unknown 이면 시간 축만 본다. unknown 이면 핸드오프를 제안하지 않는다.
- 핸드오프는 워커 세션이 스스로 결정한다. 지휘실은 빈병 교체가 2회를 넘을 때만 게이트를 연다.
- 빈병은 `handoff/<id>.json`(남은 일·판단 근거·습관 변경분·터미널 스냅샷·예산 스냅샷) + 원장 `HandoffDigest`(predecessor·budget·tool). 같은 방 n번째 빈병의 predecessor 는 n−1 번째, 자식 방 첫 빈병의 predecessor 는 자식 생성 시점 부모의 마지막 빈병. 사슬은 DAG 다.
- 후임의 최초 입력은 ROOM.md + 빈병 요약뿐이다. 이전 대화는 싣지 않는다.
- 도구 선택: 설계도 `agentTools` ∩ 잔여(`usable − used`, unknown 은 usable 로 간주)가 가장 큰 도구. 빈병 때 도구 교체가 허용되고 예산은 새 규격으로 재계산된다.

## 세대 교체 — 시뮬레이션

- 전임은 후임의 시뮬레이션이 통과할 때까지 살아 있다. 원장 방에 `successorOccupant`·`successorSession`·`handoverState`(none → simulating → passed | failed, failed → simulating)가 있고 그 밖의 전이는 오류다. passed 로 갈 때 occupant 를 successor 로 승계하고 successor 필드를 비운다.
- 재연 대상은 습관 INDEX 의 최근 N건(기본 3). 각 명령은 소유 앱 capabilities 에 `dryRun: true` 계약이 있을 때만 `--dry-run` 으로 실제 실행하고, 없으면 실행하지 않고 전임 기록(`state/term.log`·빈병 스냅샷)과 기대 출력을 대조만 한다.
- 통과 = 재연 절차 전부 일치 **그리고** 방 verdict 결과가 전임 스냅샷과 같음. 하나라도 어긋나면 실패.
- 실패의 반려 대상은 빈병이다(전임이 `handoff --amend` 로 보강). 보강 2회 초과는 사람 회부(escalated).
- 통과 시 전임 세션 종료(SIGTERM → 5초 → SIGKILL), 입주자 승계.

## 습관

- 습관 파일 `habits/<번호>-<slug>.habit.json`: title · steps(tool·command·args·dryRunSupported·expectedPattern) · verify · createdBy(빈병 id) · successCount · failureCount · lastRunAt. `INDEX.md` 는 한 줄씩, 20줄 초과분은 "… 외 N건".
- 습관은 명령이 아니다. 세션이 습관과 다르게 했으면 `habit note --deviated <번호> --reason` 으로 이유와 새 절차를 `state/notes/` 에 남겨야 한다. 노트 없는 이탈은 시뮬레이션 실패다.
- 승격: `successCount ≥ 5 && failureCount == 0`(튜닝값)이면 지휘실 세션이 테넌트 world 에 `task knowledge-candidate` 로 발행하고, 이어 `promotion publish --to gujo --confirm` 으로 공유 world 로 올린다. 두 단계 모두 사람 개입 없음. 영수증 id 는 습관 파일에 남는다.

## 테넌트와 위키

방 env 의 `AGENT_WIKI_WORLD` 는 테넌트 정책의 wikiWorld(tenant 층 world)다. personal 은 기존 `person-yun-jeonghan`, gujo·wife·silneobal 은 `tenant-<슬러그>`. 방 안에서 다른 world 로 publish 하는 것은 위키 앱이 거부한다. 인용은 위(공유 world)로만 가고 형제 테넌트를 인용할 수 없으며, 공유 world 의 변경은 테넌트로 내려오지 않는다.

## 화면

노드 = 방. 층 배치(지휘실 → 테넌트 → 상주 방 → toolbelt 타일 + 자식 방), 힘 기반 배치 없음. 상세 단계 L0(상태 칩) · L1(마지막 8줄, 2Hz) · L2(살아 있는 터미널, 뷰포트 안 가까운 순 최대 `liveTerminalCap` 개, 기본 8). 헤더에 예산 게이지·프리셋·미준수 칩·약한 벽, 아래에 빈병 사슬(2개 초과 경고색), 공존 중이면 입주자 둘. 프레임 p95 가 강등 임계(기본 24ms)를 넘으면 L2 상한을 1 줄이고 10초 안에 다시 넘지 않으면 1씩 복구한다.
