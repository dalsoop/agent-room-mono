// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GujoRoomReleaseManager",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        // helpers dual-entry: PATH CLI product (never MacOS GUI)
        .executable(name: "room-release-manager", targets: ["PartyRoomReleaseManagerCLI"]),
        .executable(name: "PartyRoomReleaseManager", targets: ["PartyRoomReleaseManager"]),
        .library(name: "PartyRoomReleaseManagerCore", targets: ["PartyRoomReleaseManagerCore"]),
    ],
    dependencies: [
        .package(path: "../../swiftkit"),
        .package(path: "../../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating", "Telemetry"]),
    ],
    targets: [
        .target(
            name: "PartyRoomReleaseManagerCore",
            dependencies: [
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "PrivilegedKit", package: "swiftkit"),
                .product(name: "StateMirrorKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ]
        ),
        .executableTarget(
            name: "PartyRoomReleaseManager",
            dependencies: [
                .product(name: "MenuBarPopoverUIKit", package: "swiftkit"),
                "PartyRoomReleaseManagerCore",
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "LaunchAtLoginKit", package: "swiftkit"),
                .product(name: "DualEntryKit", package: "swiftkit"),
                .product(name: "PermissionKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ],
            resources: [.process("Localization/Resources")]
        ),
        // Foundation-only PATH CLI — keep AppKit out (dual-entry hang 2026-07-25)
        .executableTarget(
            name: "PartyRoomReleaseManagerCLI",
            dependencies: [
                .product(name: "CommandKit", package: "swiftkit"),
                .product(name: "SingleInstanceKit", package: "swiftkit"),
                .product(name: "LocalizationKit", package: "swiftkit"),
                .product(name: "AppPathsKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
                "PartyRoomReleaseManagerCore",
                .product(name: "InteropKit", package: "swiftkit"),
                .product(name: "StateRootKit", package: "swiftkit"),
            ]
        ),
        .testTarget(
            name: "PartyRoomReleaseManagerCoreTests",
            dependencies: [
                "PartyRoomReleaseManagerCore",
                .product(name: "CommandKit", package: "swiftkit"),
            
                .product(name: "AppScaffoldKit", package: "swiftkit-appscaffold"),
            ]
        ),
    ]
)
