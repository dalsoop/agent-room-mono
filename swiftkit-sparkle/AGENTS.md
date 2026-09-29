# swiftkit-sparkle

Sparkle 2 자동 업데이트를 앱에 붙이는 얇은 래퍼 킷 패키지다. 제품은 `SparkleUpdateKit` 하나이고, `swiftkit`(AppWindowKit·LocalizationKit·SettingsUIKit)과 Sparkle(`from: "2.7.0"`)을 의존한다.

## 범위

- 업데이터 호스트(`SparkleUpdaterHost`), SwiftUI 수정자(`.sparkleUpdates()`), 앱 델리게이트 연결, 피드 주소 읽기(`SparkleFeedURL`: 번들 `Info.plist`의 `SUFeedURL`과 공개 EdDSA 키), 업데이트 설정 화면, 현지화 문자열, 수신 부트스트랩.
- iOS에서는 빌드되지 않는 자리 표시(`IOSUnavailable`).

## 범위 밖

- 업데이트 피드(appcast) 생성·서명·업로드. 이 저장소 밖의 배포 도구가 맡는다.
- 스캐폴드 쪽 켜기·끄기. 앱은 이 패키지를 직접 부르기보다 `swiftkit-appscaffold`의 `SelfUpdating` 트레잇으로 켠다.

## 불변식

- 이 패키지는 `swiftkit`만 로컬 의존한다. `swiftkit-appscaffold`를 의존하면 순환이 생긴다.
- 플랫폼 선언은 `swiftkit`과 같은 macOS 15·iOS 18이다. 선언을 빼면 iOS 기본값이 낮아져, 이 패키지가 그래프에 들어오는 iOS 빌드가 매니페스트 검증에서 깨진다(`Package.swift` 주석).
- `SUFeedURL`은 공개 배포 빌드에서만 번들에 들어간다. 개발 빌드에서 `SparkleFeedURL.current`가 nil인 것은 정상이다.

## 테스트

- 패키지 테스트는 Swift Testing 3건이다. 2026-09-30 통과.
- 피드 주소·설정 변경은 번들 값 없이도 크래시하지 않는지 확인한다. 실제 네트워크로 appcast를 받는 테스트를 만들지 않는다.
