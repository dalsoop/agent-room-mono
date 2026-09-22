# Party Room Release Manager

파티룸(`game-party-room-app`) **멀티 플랫폼 배포**를 관리하는 macOS 메뉴바 앱.

> **일반화 후속**: 여러 오픈소스 앱을 같은 방식으로 다루려면
> **[Open Source App Publisher](../open-source-app-publisher-swift/)**
> (`open-source-app-publisher` CLI, 프리셋 `party-room`) 를 쓰세요.
> 본 앱은 파티룸 전용 축소판으로 **유지**합니다(삭제 예정 아님).
> 공개 바이너리: https://github.com/dalsoop/party-room/releases

## 하는 일

| 기능 | 설명 |
|---|---|
| 소스 프로브 | `pubspec` · android/ios/macos/windows · flutter/gh PATH |
| 플랫폼 빌드 | Android APK · macOS (`tools/release.sh` 서명·공증·DMG) · Windows · iOS IPA |
| 산출물 스캔 | 빌드 결과 경로 표시 · Finder 열기 |
| GitHub 힌트 | `gh release create …` 템플릿 |

## 비목표

- iOS 사이드로드 해결(TestFlight/App Store 영역)
- 사내 전체 함대 ship (그건 App Build Manager)

## CLI

```bash
party-room-release-manager status
party-room-release-manager build android
party-room-release-manager build macos
party-room-release-manager release-hint
party-room-release-manager config path /path/to/game-party-room-app
```

## 기본 소스 경로

`~/Documents/WORK/WORKSPACE/apps/flutter-app-mono/main/apps/game-party-room-app`

설정: `~/.party-room-release-manager/config.json`

## 개발

```bash
cd apps/party-room-release-manager-swift
swift test
# ship
app-build-manager ship apps/party-room-release-manager-swift release
```
