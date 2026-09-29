# room-release-manager

파티룸 Flutter 앱(`game-party-room-app`, flutter-app-mono 안)의 Android·macOS·Windows·iOS 빌드와 GitHub Release 초안을 한 메뉴바 앱과 CLI에서 다루는 macOS 앱이다. 방(room) 체제와는 관계가 없다. PATH CLI와 번들 id는 `room-release-manager`/`net.ranode.room-release-manager`이고, 코드 안의 앱 이름·`capabilities`·StateMirror·헬스 펄스 이름은 `party-room-release-manager`, 타깃 이름은 `PartyRoomReleaseManager*`다.

## 범위

- `PartyRoomReleaseManagerCore`: 설정(`PartyRoomReleaseConfig`, `config.json`), 소스·도구·산출물 프로브, 플랫폼별 빌드, GitHub Release 명령 초안, Finder 열기, StateMirror 게시.
- `PartyRoomReleaseManager`(GUI): 메뉴바 팝오버와 주 창, 설정.
- `PartyRoomReleaseManagerCLI`: `status`·`probe`·`build`·`release-hint`·`open-project`·`open-artifacts`·`config`·`capabilities`·`version`·`help`·`open`.

## 범위 밖

- 파티룸 앱의 소스. 이 앱은 flutter-app-mono의 프로젝트 경로를 읽고 그 안에서 명령을 돌릴 뿐, 소스를 고치지 않는다.
- GitHub Release 생성 실행. `gh release create` 초안 문자열만 준다.
- 함대 앱 배포(`app-build-manager`의 일), iOS 사이드로드.
- 방 체제 앱(터미널·관측판·격리기)과 방 관련 킷. 이 앱에서 방 킷을 의존하지 않는다.

## 불변식

- 빌드는 프로젝트 경로가 있고, Flutter 실행 파일을 찾았고, `flutter pub get`이 성공했을 때만 진행한다. 하나라도 아니면 `(false, 로그)`를 돌려주고 CLI는 exit 1이다.
- Flutter 찾기 순서: `which flutter` → `which fvm`(찾으면 `fvm flutter …`로 실행) → Homebrew 경로. 셋 다 없으면 빌드하지 않는다.
- macOS 빌드는 프로젝트의 `tools/release.sh`가 있으면 그 스크립트(서명·공증·DMG), 없으면 `flutter build macos --release`다.
- 산출물 판정은 플랫폼별 후보 경로(`build/app/outputs/flutter-apk/app-release.apk`, `build/release/PartyRoom.dmg`, `build/windows/x64/runner/Release`, `build/ios/ipa` 등) 중 처음 존재하는 것이다.
- 설정 파일은 StateRootKit 루트의 `.party-room-release-manager/config.json`이다. 기본 프로젝트 경로는 홈 아래 `Documents/WORK/WORKSPACE/apps/flutter-app-mono/main/apps/game-party-room-app`, 기본 저장소는 `dalsoop/party-room`이다.
- 헬스 펄스는 `~/.swift-app-state/pulse/party-room-release-manager.pulse`다. GUI 시작과 모든 CLI 실행이 쓴다.
- 셸 명령이 필요한 곳(`fvm` 실행, `release.sh`)은 `CommandKit.ShellCommand`와 인자 따옴표 처리(`shellQuote`)를 거친다. `bash -lc`를 직접 만들지 않는다.

## 구현 패턴

- 경로 상수는 `PartyRoomReleaseDefaults`·`PartyRoomHostTools`·`PartyRoomBuildLayout`에 모은다. 새 경로를 코드 중간에 문자열로 쓰지 않는다.
- 명령 실행은 주입된 러너(`runner.run(exe, args, cwd:)`)로 한다. `release.sh`만 `ShellCommand.run`을 직접 부르므로 테스트에서 가짜로 바꿀 수 없다.
- CLI 명령을 더하면 사용법 문자열, `capabilities`의 `commands`, 메뉴바·주 창의 같은 동작을 함께 더한다.

## 알려진 상태 (2026-09-30)

- CLI `main.swift`의 `open` 분기에 `SafeProcessRunner` 치환 잔해(짝 없는 `} catch {`)가 있어 CLI 타깃이 컴파일되지 않는다.
- CLI `open`은 `open -b net.ranode.party-room-release-manager`로 GUI를 찾는데 `Info.plist`의 번들 id는 `net.ranode.room-release-manager`다.
- 기본 프로젝트 경로가 `homeDirectoryForCurrentUser`로 조립된다(StateRootKit을 거치지 않는다).
- `Info.plist` 버전(1.0.8)이 `CHANGELOG.md`(1.0.9)보다 낮다.

## 테스트

- `Tests/PartyRoomReleaseManagerCoreTests/SmokeTests.swift`(XCTest 5개): 형식 계약, 기본 설정 경로, 플랫폼별 Flutter 대상, 경로 없는 프로브(가짜 러너), release 힌트의 저장소 이름. 빌드 경로(`build`)를 검사하는 테스트는 없다. 실제 `flutter`·`gh`를 부르는 테스트를 만들지 않는다.
- 새 플랫폼·경로를 더할 때 확인할 것: 프로젝트 경로가 없을 때 빌드가 시작되지 않는지, `pub get` 실패에서 멈추는지, `fvm` 경로가 `fvm flutter`로 바뀌는지, 산출물 후보 순서.
