# 0003. 앱 공용 스캐폴드는 별도 킷 패키지에 두고 트레잇으로 켠다

**상황**: 판매 앱은 Sparkle 자동 업데이트가 필요한데 Sparkle은 `swiftkit-sparkle`에만 있고, 그 패키지는 `swiftkit`을 의존한다. 스캐폴드를 `swiftkit` 안에 두고 Sparkle을 의존하면 패키지 순환이 생긴다. 실측 오류는 `cyclic dependency declaration found: app -> Core -> Wrap -> Core`였고, 트레잇으로 꺼도 매니페스트 그래프에서 순환으로 잡혔다(`swiftkit-appscaffold/Package.swift` 주석).

**결정**: 스캐폴드를 세 번째 패키지 `swiftkit-appscaffold`로 빼서 `appscaffold → sparkle → swiftkit`, `appscaffold → swiftkit`의 비순환 그래프로 만든다. Sparkle·Cloud Apps 관리·Telemetry는 트레잇(`SelfUpdating`, `GujoManaged`, `Telemetry`)으로 켜고, 기본값은 이 패키지에서 셋 다 켠다.

**대안**: `swiftkit` 안에 스캐폴드를 두고 Sparkle 의존을 트레잇으로 끄는 방식. 트레잇을 꺼도 순환 오류가 나서 쓸 수 없었다.

**결과**: 트레잇 때문에 이 패키지만 tools-version 6.1이 필요하다. 앱이 `traits:`를 적으면 기본값이 꺼지므로, 이 저장소의 방 앱 셋은 Telemetry가 꺼진 상태다. 트레잇이 꺼진 모듈은 빌드되지 않는다.
