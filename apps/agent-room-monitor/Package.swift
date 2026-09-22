// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoAgentRoomMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "agent-room-monitor", targets: ["AgentRoomMonitorCLI"]),
        .executable(name: "AgentRoomMonitor", targets: ["AgentRoomMonitor"]),
        .library(name: "AgentRoomMonitorCore", targets: ["AgentRoomMonitorCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-sparkle"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating"]),
    ],
    targets: [
        .target(
            name: "AgentRoomMonitorCore",
            // identity-single-source 정본 — AgentOccupant(hostName 해석)는 RoomKit 에서만 조립한다.
            dependencies: [
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "PrivilegedKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "AgentSessionKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
            ]
        ),
        .executableTarget(
            name: "AgentRoomMonitor",
            dependencies: [
                "AgentRoomMonitorCore",
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "OnboardingUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "SparkleUpdateKit", package: "swiftkit-sparkle"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "RoomKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ],
            exclude: ["HexBoard.swift"],
            resources: [
                .process("Localization/Resources"),
                .process("Mascots"),
            ]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25)
        .executableTarget(
            name: "AgentRoomMonitorCLI",
            dependencies: [
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "AgentCLIKit", package: "swiftkit"),
            
                .product(name: "LocalizationKit", package: "swiftkit"),
                "AgentRoomMonitorCore",
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
        .testTarget(
            name: "AgentRoomMonitorCoreTests",
            dependencies: [
                "AgentRoomMonitorCore",
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
