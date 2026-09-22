import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "AgentRoomTerminal",
    guiName: "AgentRoomTerminal",
    cliName: "agent-room-terminal",
    coreDependencies: [
        .project(target: "AgentSessionKit", path: "//swiftkit"),
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InstallHealthKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "PackageIdentityKit", path: "//swiftkit"),
        .project(target: "PrivilegedKit", path: "//swiftkit"),
        .project(target: "RoomKit", path: "//swiftkit"),
        .project(target: "SandboxKit", path: "//swiftkit"),
        .project(target: "SecretMaskKit", path: "//swiftkit"),
        .project(target: "SessionKit", path: "//swiftkit"),
        .project(target: "StateMirrorKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit"),
        .project(target: "TerminalEngineKit", path: "//swiftkit-terminal")
    ],
    cliDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "RoomKit", path: "//swiftkit"),
        .project(target: "SandboxKit", path: "//swiftkit"),
        .project(target: "SecretMaskKit", path: "//swiftkit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "ClipboardActionUIKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "DualEntryKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LaunchAtLoginKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "NoticeBannerUIKit", path: "//swiftkit"),
        .project(target: "OnboardingUIKit", path: "//swiftkit"),
        .project(target: "PackageIdentityKit", path: "//swiftkit"),
        .project(target: "PermissionKit", path: "//swiftkit"),
        .project(target: "RadialGraphUIKit", path: "//swiftkit"),
        .project(target: "RoomKit", path: "//swiftkit"),
        .project(target: "SandboxKit", path: "//swiftkit"),
        .project(target: "SecretMaskKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SingleInstanceKit", path: "//swiftkit"),
        .project(target: "SparkleUpdateKit", path: "//swiftkit-sparkle"),
        .project(target: "StateRootKit", path: "//swiftkit"),
        .project(target: "TerminalEngineGhostty", path: "//swiftkit-terminal"),
        .project(target: "TerminalEngineKit", path: "//swiftkit-terminal"),
        .project(target: "TerminalEngineSwiftTerm", path: "//swiftkit-terminal"),
        .project(target: "TimelineGraphUIKit", path: "//swiftkit")
    ],
    testDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "RoomKit", path: "//swiftkit"),
        .project(target: "SandboxKit", path: "//swiftkit"),
        .project(target: "SecretMaskKit", path: "//swiftkit"),
        .project(target: "TerminalEngineKit", path: "//swiftkit-terminal"),
        .target(name: "AgentRoomTerminalDaemon")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/AgentRoomTerminal/Localization/Resources/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/AgentRoomTerminal.entitlements")
)
