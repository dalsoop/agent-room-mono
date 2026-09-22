// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentRoomIsolator",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "agent-room-isolator", targets: ["AgentRoomWorktreeCLI"]),
        .executable(name: "AgentRoomWorktree", targets: ["AgentRoomWorktree"]),
        .library(name: "AgentRoomWorktreeCore", targets: ["AgentRoomWorktreeCore"]),
    ],
    dependencies: [
        .package(path: "../../Common/System"),
        .package(path: "../../Common/CLI"),
        .package(path: "../../Common/UI"),
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-sparkle"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating"]),
    ],
    targets: [
        .target(
            name: "AgentRoomWorktreeCore",
            dependencies: [
                .product(name: "CommonSystem", package: "System"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ]
        ),
        .executableTarget(
            name: "AgentRoomWorktree",
            dependencies: [
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                "AgentRoomWorktreeCore",
                .product(name: "CommonUI", package: "UI"),
                .product(name: "SparkleUpdateKit", package: "swiftkit-sparkle"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "NoticeBannerUIKit", package: "swiftkit"),
                .product(name: "OnboardingUIKit", package: "swiftkit"),
                .product(name: "StatusIndicatorUIKit", package: "swiftkit"),
                .product(name: "ClipboardActionUIKit", package: "swiftkit"),
                .product(name: "WindowChromeKit", package: "swiftkit"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25).
        // LocalizationKit: 출력 문자열 i18n(CLILocalization) — 앱 카탈로그를 공유한다.
        // AgentRoomWorktreeCore: Foundation 전용(quality core-purity) — 상태 경로 정본(AppPaths)을
        // CLI capabilities.state 도 같은 곳에서 읽는다(홈·테넌트 해석 두 벌 금지).
        .executableTarget(
            name: "AgentRoomWorktreeCLI",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                "AgentRoomWorktreeCore",
                .product(name: "CommonCLI", package: "CLI"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AgentCLIKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            ]
        ),
        .testTarget(
            name: "AgentRoomWorktreeCoreTests",
            dependencies: [
                "AgentRoomWorktreeCore",
                .product(name: "CommonSystem", package: "System"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
