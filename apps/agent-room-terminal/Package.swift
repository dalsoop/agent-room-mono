// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentRoomTerminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "agent-room-terminal", targets: ["AgentRoomTerminalCLI"]),
        .executable(name: "AgentRoomTerminal", targets: ["AgentRoomTerminal"]),
        .executable(name: "agent-room-terminal-daemon", targets: ["AgentRoomTerminalDaemon"]),
        .library(name: "AgentRoomTerminalCore", targets: ["AgentRoomTerminalCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-sparkle"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating"]),
        .package(path: "../../swiftkit-terminal"),
    ],
    targets: [
        .target(
            name: "AgentRoomTerminalCore",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "PrivilegedKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "SandboxKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                // 상태 경로 정본 — AppPaths 가 홈 대신 StateRootKit 루트 아래로 조립한다.
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "PackageIdentityKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "SecretMaskKit", package: "swiftkit"),
                .product(name: "AgentSessionKit", package: "swiftkit"),
                .product(name: "SessionKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "InstallHealthKit", package: "swiftkit"),
                .product(name: "TerminalEngineKit", package: "swiftkit-terminal"),
            ]
        ),
        .executableTarget(
            name: "AgentRoomTerminal",
            dependencies: [
                "AgentRoomTerminalCore",
                .product(name: "TerminalEngineKit", package: "swiftkit-terminal"),
                .product(name: "TerminalEngineGhostty", package: "swiftkit-terminal"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "ClipboardActionUIKit", package: "swiftkit"),
                .product(name: "NoticeBannerUIKit", package: "swiftkit"),
                .product(name: "OnboardingUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "SparkleUpdateKit", package: "swiftkit-sparkle"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "PackageIdentityKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "SecretMaskKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "RadialGraphUIKit", package: "swiftkit"),
                .product(name: "TimelineGraphUIKit", package: "swiftkit"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25).
        // LocalizationKit: 출력 문자열 i18n(CLILocalization) — 앱 카탈로그를 공유한다.
        // AgentRoomTerminalCore: Foundation 전용(quality core-purity) — 상태 경로 정본(AppPaths)을
        // CLI capabilities.state 도 같은 곳에서 읽는다(홈·테넌트 해석 두 벌 금지).
        .executableTarget(
            name: "AgentRoomTerminalCLI",
            dependencies: [
                "AgentRoomTerminalCore",
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "SandboxKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "SecretMaskKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
            ]
        ),
        // SwiftTerm + headless Terminal — explicit exception to Foundation-only CLI.
        // PATH CLI target AgentRoomTerminalCLI must not link SwiftTerm.
        .executableTarget(
            name: "AgentRoomTerminalDaemon",
            dependencies: [
                "AgentRoomTerminalCore",
                .product(name: "TerminalEngineSwiftTerm", package: "swiftkit-terminal"),
                .product(name: "SandboxKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "PackageIdentityKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "ProcessLifecycleKit", package: "swiftkit"),
            ]
        ),
        .testTarget(
            name: "AgentRoomTerminalCoreTests",
            dependencies: [
                "AgentRoomTerminalCore",
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "SecretMaskKit", package: "swiftkit"),
                .product(name: "TerminalEngineKit", package: "swiftkit-terminal"),
            ],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "AgentRoomTerminalDaemonTests",
            dependencies: [
                "AgentRoomTerminalDaemon",
                "AgentRoomTerminalCore",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "SandboxKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
        .testTarget(
            name: "AgentRoomTerminalSmokeTests",
            dependencies: [
                "AgentRoomTerminalCore",
                "AgentRoomTerminalCLI",
                "AgentRoomTerminalDaemon",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
