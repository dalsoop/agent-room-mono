import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.dualEntryApp(
    name: "Party Room Release Manager",
    guiName: "PartyRoomReleaseManager",
    cliName: "party-room-release-manager",
    coreDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "CommandKit", path: "//swiftkit"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "PrivilegedKit", path: "//swiftkit"),
        .project(target: "StateMirrorKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    cliDependencies: [
        .project(target: "AppPathsKit", path: "//swiftkit"),
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "InteropKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    guiDependencies: [
        .project(target: "AppScaffoldKit", path: "//swiftkit-appscaffold"),
        .project(target: "DualEntryKit", path: "//swiftkit"),
        .project(target: "LaunchAtLoginKit", path: "//swiftkit"),
        .project(target: "LocalizationKit", path: "//swiftkit"),
        .project(target: "MenuBarPopoverUIKit", path: "//swiftkit"),
        .project(target: "PermissionKit", path: "//swiftkit"),
        .project(target: "SettingsUIKit", path: "//swiftkit"),
        .project(target: "SingleInstanceKit", path: "//swiftkit"),
        .project(target: "StateRootKit", path: "//swiftkit")
    ],
    testDependencies: [
        .project(target: "CommandKit", path: "//swiftkit")
    ],
    guiResources: [
        "Packaging/AppIcon.icns",
        "Sources/PartyRoomReleaseManager/Localization/Resources/**"
    ],
    infoPlist: .file(path: "Packaging/Info.plist"),
    entitlements: .file(path: "Packaging/PartyRoomReleaseManager.entitlements")
)
