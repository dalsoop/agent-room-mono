import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "AgentRoomWorktree",
    guiName: "AgentRoomWorktree",
    cliName: "agent-room-worktree",
    coreDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "CommonSystem", path: "//Common"),
        .project(target: "StateMirrorKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    cliDependencies: [
        .project(target: "AgentCLIKit", path: "//swiftkit"),
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "CommonCLI", path: "//Common"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "ClipboardActionUIKit", path: "//swiftkit"),
        .project(target: "CommonUI", path: "//Common"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "NoticeBannerUIKit", path: "//swiftkit"),
        .project(target: "OnboardingUIKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SparkleUpdateKit", path: "//swiftkit-sparkle"),
        .project(target: "StatusIndicatorUIKit", path: "//swiftkit"),
        .project(target: "WindowChromeKit", path: "//swiftkit")
    ],
    testDependencies: [
        .project(target: "CommonSystem", path: "//Common")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/AgentRoomWorktree/Localization/Resources/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/AgentRoomWorktree.entitlements")
)
