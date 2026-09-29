# 0002. 터미널 엔진은 별도 킷 패키지 `swiftkit-terminal`에 둔다

**상황**: 방 터미널은 SwiftTerm(CPU PTY 렌더러)과 libghostty-spm(Metal GPU 렌더러)을 쓴다. 두 패키지는 C·Zig·Metal 빌드를 끌고 오는 무거운 원격 의존이다. 공용 킷 `swiftkit`은 모든 앱이 의존하므로, 여기에 넣으면 터미널을 쓰지 않는 앱도 해석·빌드 비용을 진다(`swiftkit-terminal/Package.swift` 주석).

**결정**: 엔진 프로토콜과 값 타입(`TerminalEngineKit`, 원격 의존 없음)과 두 구현(`TerminalEngineSwiftTerm`, `TerminalEngineGhostty`)을 `swiftkit-terminal` 패키지에 모은다. SwiftTerm은 1.13.0으로, libghostty-spm은 커밋 리비전으로 고정한다.

**대안**: `swiftkit` 안에 엔진을 두는 것. 위 비용 때문에 택하지 않았다.

**결과**: 엔진을 쓰는 앱만 `../../swiftkit-terminal`을 의존한다. 엔진 버전은 이 패키지에서만 바꾼다.
