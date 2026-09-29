# 0001. PATH CLI 타깃은 UI 킷과 터미널 엔진을 직접 의존하지 않는다

**상황**: 앱마다 GUI 실행 파일과 PATH CLI가 함께 있다(이중 진입). 2026-07-25에 PATH가 앱 번들의 GUI 실행 파일(`Contents/MacOS`)을 가리키거나 CLI가 AppKit을 끌어오면서 CLI 호출이 멈추는 사고가 있었다(각 `Package.swift`의 "dual-entry hang 2026-07-25" 주석).

**결정**: 앱마다 실행 타깃을 GUI와 CLI로 나누고, CLI 타깃의 소스는 AppKit·SwiftUI를 import하지 않고, UI 킷을 직접 의존하지 않는다(매니페스트 주석의 표현은 "Foundation-only PATH CLI — keep AppKit out"). PATH에는 번들의 `Contents/Helpers/<cli>`만 올린다. 터미널 엔진이 필요한 방 터미널은 PTY를 세 번째 실행 파일(데몬)에 두고, 데몬만 SwiftTerm을, GUI만 Ghostty를 링크한다.

**대안**: PATH가 앱 번들의 GUI 실행 파일(`Contents/MacOS`)을 가리키게 하는 방식. 사고의 원인이라 금지됐다(`DualEntryKit`의 "PATH→MacOS 금지" 계약).

**결과**: CLI는 화면을 그리거나 터미널을 직접 파싱할 수 없다. 터미널 출력이 필요한 CLI 명령(`snapshot`, `exec`, `attach`)은 데몬 소켓을 거쳐야 한다. CLI 타깃 의존 목록에 UI 킷이 들어가면 이 결정 위반이다. 다만 모든 CLI가 의존하는 `AppScaffoldKit`에는 SwiftUI를 import하는 파일이 있어, SwiftUI 자체는 간접으로 링크된다.
