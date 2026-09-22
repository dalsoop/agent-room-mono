import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "AgentRoomMonitor",
    guiName: "AgentRoomMonitor",
    cliName: "agent-room-monitor",
    coreDependencies: [
        .project(target: "AgentSessionKit", path: "//swiftkit"),
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "PrivilegedKit", path: "//swiftkit"),
        .project(target: "RoomKit", path: "//swiftkit"),
        .project(target: "StateMirrorKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    cliDependencies: [
        .project(target: "AgentCLIKit", path: "//swiftkit"),
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "DualEntryKit", path: "//swiftkit"),
        .project(target: "LaunchAtLoginKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "OnboardingUIKit", path: "//swiftkit"),
        .project(target: "PermissionKit", path: "//swiftkit"),
        .project(target: "RoomKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SingleInstanceKit", path: "//swiftkit"),
        .project(target: "SparkleUpdateKit", path: "//swiftkit-sparkle")
    ],
    testDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "CommandKit", path: "//swiftkit")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/AgentRoomMonitor/Localization/Resources/**",
        "Sources/AgentRoomMonitor/Mascots/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/AgentRoomMonitor.entitlements")
)
