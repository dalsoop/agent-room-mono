// swift-tools-version: 6.1
import PackageDescription

// swiftkit-terminal: 터미널 렌더러 및 PTY 프로세스 추상화 키트.
//
// swiftkit 본체는 "외부 의존성 0건"을 불변량으로 지킨다.
// SwiftTerm 및 libghostty-spm과 같은 외부 C/Zig/Metal 기반 무거운 터미널 엔진 의존성을
// 이 별도 패키지로 분리하여 비사용 앱에 SPM 의존성 전파를 차단한다.
//
// 3대 제품 구성:
// - TerminalEngineKit: 외부 의존 0건. 프로토콜(TerminalEngine, TerminalEngineEvents),
//   값 타입(TerminalLaunch, TerminalAppearance, TmuxBacking, PaneSandbox 등) 제공.
// - TerminalEngineSwiftTerm: SwiftTerm (1.13.0 고정) 기반 CPU PTY 터미널 구현체.
// - TerminalEngineGhostty: libghostty-spm (Metal 120Hz GPU 렌더러) 및 인메모리 스트림 바인딩.
let package = Package(
    name: "swiftkit-terminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TerminalEngineKit", targets: ["TerminalEngineKit"]),
        .library(name: "TerminalEngineSwiftTerm", targets: ["TerminalEngineSwiftTerm"]),
        .library(name: "TerminalEngineGhostty", targets: ["TerminalEngineGhostty"]),
    ],
    dependencies: [
        .package(path: "../swiftkit"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.13.0"),
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", revision: "a2565ccf047c03c74a59dd7c16a8fac7c477852f"),
    ],
    targets: [
        .target(
            name: "TerminalEngineKit",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ]
        ),
        .target(
            name: "TerminalEngineSwiftTerm",
            dependencies: [
                "TerminalEngineKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(
            name: "TerminalEngineGhostty",
            dependencies: [
                "TerminalEngineKit",
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyKit", package: "libghostty-spm"),
            ]
        ),
        .testTarget(
            name: "TerminalEngineKitTests",
            dependencies: ["TerminalEngineKit"]
        ),
        .testTarget(
            name: "TerminalEngineGhosttyTests",
            dependencies: [
                "TerminalEngineKit",
                "TerminalEngineGhostty",
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyKit", package: "libghostty-spm"),
            ]
        ),
    ]
)
