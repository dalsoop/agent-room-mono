# swiftkit-appscaffold

앱 공용 진입 스캐폴드와 판매 앱 관리 기능을 담은 킷 패키지다. 제품은 `AppScaffoldKit` 하나이고, 트레잇 셋(`GujoManaged`, `SelfUpdating`, `Telemetry`)으로 기능을 켠다. 기본 트레잇은 셋 다 켜짐이다. `swiftkit`과 `swiftkit-sparkle`을 의존한다.

## 범위

- 앱 진입 틀: `RanodeApp`(창 앱), `RanodeMenuBarApp`·`RanodeMenuBarExtraApp`·`RanodeMenuBarPopover`(메뉴바 앱), `RanodeWindowGroupApp`, 설정 창 호스트, 형식 계약(`RanodeAppFormContract`)과 정적 분석(`ScaffoldAnalyzer`).
- 판매 앱 관리: `GujoManaged`(Cloud Apps 관리, CLI 진입의 `exitIfNotEntitledSync`), App Store·Play Billing·개인 라이선스 관리 경로, 서명된 라이선스, 자격(`Entitlement`).
- 테넌트 상태 루트 부트스트랩(`TenantStateRootBootstrap`: `SWIFT_APP_STATE_ROOT`를 정하는 진입점).
- 설명서: `Documentation/gujo-managed.md`, `channel-entitlements.md`, `play-billing-android.md`.

## 범위 밖

- 앱 도메인 로직과 앱별 화면.
- Sparkle 자체(`swiftkit-sparkle`), 크래시 수집 구현(`swiftkit`의 TelemetryKit).
- `swiftkit`에 넣는 것. 이 킷을 `swiftkit` 안으로 옮기면 Sparkle 의존 때문에 패키지 순환이 생긴다.

## 불변식

- 의존 그래프는 `appscaffold → sparkle → swiftkit`, `appscaffold → swiftkit`이다. `swiftkit`이나 `swiftkit-sparkle`이 이 패키지를 의존하면 안 된다.
- 트레잇 기본값은 이 패키지의 `traits: [.default(enabledTraits: [...])]` 한 곳에서 정한다. 소비자가 `traits:`를 적으면 기본값이 꺼지고 적은 것만 켜진다. 꺼진 트레잇의 모듈(`SparkleUpdateKit`, `TelemetryKit`)은 빌드되지 않는다.
- `GujoManaged.exitIfNotEntitledSync()`는 CLI 진입의 첫 줄이며 동기 함수다. 2026-09-21 라이선스 게이트 퇴역 뒤로 막지 않고, 설치본이 소스보다 낡았으면 stderr 경고만 낸다(`SWIFT_APP_FAIL_CLOSED_STALE=1`이면 exit 70). async 판을 CLI 최상위에서 `await`하지 않는다. 그러면 파일 전체가 async 문맥이 되어 `Thread.sleep` 같은 noasync API를 쓰는 CLI가 컴파일되지 않는다.
- `help`·`version`·`capabilities`는 어떤 관리 게이트에도 막히지 않는다.
- `RanodeApp.swift`는 `SettingsUIKit`·`SingleInstanceKit`을 재수출하고 SwiftUI를 import한다. 이 킷을 의존하는 CLI에도 SwiftUI가 간접으로 링크되므로, CLI 진입점에서 스캐폴드의 SwiftUI 타입을 부르지 않는다.

## 구현 패턴

- 트레잇에 묶인 코드는 `#if <트레잇>`으로 감싸고, 의존 제품은 `condition: .when(traits: [...])`로 건다.
- 플랫폼 한정 의존(`PermissionKit`)은 `condition: .when(platforms: [.macOS])`와 `#if canImport(...)`를 함께 쓴다.

## 테스트

- 패키지 테스트는 Swift Testing 74건(10개 묶음)이다. 2026-09-30 통과.
- 앱 형식 계약은 `RanodeAppContractTestCase`를 앱 테스트가 상속해 확인한다(각 앱의 `testAppFormContractCompliance`).
- 트레잇 조합을 바꾸면 기본 트레잇과 `GujoManaged`·`SelfUpdating`만 켠 조합 둘 다 빌드되는지 확인한다(이 저장소의 방 앱 셋이 뒤의 조합이다).
