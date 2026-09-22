import Foundation
import StateRootKit
import LocalizationKit

/// 파티룸 배포 대상 플랫폼.
public enum PartyRoomPlatform: String, CaseIterable, Sendable, Identifiable, Codable {
    case android
    case macos
    case windows
    case ios

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .android: return "Android"
        case .macos: return "macOS"
        case .windows: return "Windows"
        case .ios: return "iOS"
        }
    }

    /// flutter build 서브커맨드.
    public var flutterTarget: String {
        switch self {
        case .android: return "apk"
        case .macos: return "macos"
        case .windows: return "windows"
        case .ios: return "ipa"
        }
    }

    public var systemImage: String {
        switch self {
        case .android: return "smartphone"
        case .macos: return "desktopcomputer"
        case .windows: return "pc"
        case .ios: return "iphone"
        }
    }

    /// 산출물 후보 (상대경로, 짧은 라벨).
    public var artifactCandidates: [(relativePath: String, note: String)] {
        switch self {
        case .android:
            return [
                (PartyRoomBuildLayout.androidApkFlutter, "APK"),
                (PartyRoomBuildLayout.androidApkLegacy, "APK"),
            ]
        case .macos:
            return [
                (PartyRoomBuildLayout.macosDmg, "DMG (release.sh)"),
                (PartyRoomBuildLayout.macosApp, "app"),
            ]
        case .windows:
            return [
                (PartyRoomBuildLayout.windowsRelease, "Release folder"),
            ]
        case .ios:
            return [
                (PartyRoomBuildLayout.iosIpaDir, "ipa dir"),
            ]
        }
    }

    public var missingArtifactHint: String {
        switch self {
        case .android: return "flutter build apk --release"
        case .macos: return CLILocalization.string("Models.return")
        case .windows: return CLILocalization.string("Models.return-2")
        case .ios: return CLILocalization.string("Models.return-3")
        }
    }
}

/// 설정 기본값 — 워크스페이스 경로·저장소 slug 를 한곳에.
public enum PartyRoomReleaseDefaults {
    /// 홈 기준 game-party-room-app 상대 경로.
    public static let projectPathFromHome =
        "Documents/WORK/WORKSPACE/apps/flutter-app-mono/main/apps/game-party-room-app"
    public static let githubRepo = "dalsoop/party-room"
    public static let versionHint = "1.0.0"
    public static let defaultBranch = "main"
    public static let appBundleID = "net.ranode.party-room-release-manager"
}

/// 시스템·PATH 도구 경로. 호출부에서 절대경로를 다시 쓰지 않는다.
public enum PartyRoomHostTools {
    public static let open = "/usr/bin/open"
    public static let which = "/usr/bin/which"
    public static let flutter = "flutter"
    public static let fvm = "fvm"
}

/// Flutter 트리·산출물 상대 경로 (프로브·빌드·Finder 가 같이 씀).
public enum PartyRoomBuildLayout {
    public static let pubspec = "pubspec.yaml"
    public static let releaseScript = "tools/release.sh"
    public static let androidDir = "android"
    public static let macosDir = "macos"
    public static let windowsDir = "windows"
    public static let iosDir = "ios"
    public static let buildDir = "build"
    public static let buildReleaseDir = "build/release"
    public static let flutterApkDir = "build/app/outputs/flutter-apk"
    public static let androidApkFlutter = "build/app/outputs/flutter-apk/app-release.apk"
    public static let androidApkLegacy = "build/app/outputs/apk/release/app-release.apk"
    public static let macosDmg = "build/release/PartyRoom.dmg"
    public static let macosApp = "build/macos/Build/Products/Release/PartyRoom.app"
    public static let windowsRelease = "build/windows/x64/runner/Release"
    public static let iosIpaDir = "build/ios/ipa"
}

/// 앱 설정 (소스 경로·GitHub·버전).
public struct PartyRoomReleaseConfig: Codable, Sendable, Equatable {
    /// game-party-room-app 루트 (pubspec.yaml 있는 곳).
    public var projectPath: String
    /// 예: dalsoop/party-room
    public var githubRepo: String
    /// pubspec / 릴리스 태그 힌트
    public var versionHint: String
    /// 기본 브랜치 이름
    public var defaultBranch: String

    public init(
        projectPath: String = PartyRoomReleaseConfig.defaultProjectPath,
        githubRepo: String = PartyRoomReleaseDefaults.githubRepo,
        versionHint: String = PartyRoomReleaseDefaults.versionHint,
        defaultBranch: String = PartyRoomReleaseDefaults.defaultBranch
    ) {
        self.projectPath = projectPath
        self.githubRepo = githubRepo
        self.versionHint = versionHint
        self.defaultBranch = defaultBranch
    }

    public static var defaultProjectPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/\(PartyRoomReleaseDefaults.projectPathFromHome)"
    }

    public static var storeURL: URL {
        StateRootKit.url(".party-room-release-manager/config.json")
    }
}

/// 플랫폼별 산출물 상태.
public struct PlatformArtifactStatus: Sendable, Identifiable, Equatable {
    public var id: String { platform.rawValue }
    public var platform: PartyRoomPlatform
    public var ready: Bool
    public var path: String?
    public var note: String

    public init(platform: PartyRoomPlatform, ready: Bool, path: String? = nil, note: String = "") {
        self.platform = platform
        self.ready = ready
        self.path = path
        self.note = note
    }
}

/// 소스 트리 점검 결과.
public struct ProjectProbe: Sendable, Equatable {
    public var projectPath: String
    public var exists: Bool
    public var hasPubspec: Bool
    public var hasReleaseScript: Bool
    public var hasAndroid: Bool
    public var hasMacOS: Bool
    public var hasWindows: Bool
    public var hasIOS: Bool
    public var flutterOnPath: Bool
    public var ghOnPath: Bool
    public var artifacts: [PlatformArtifactStatus]
    public var summaryLine: String

    public var isHealthy: Bool {
        let hasAnyPlatform = hasAndroid || hasMacOS || hasWindows || hasIOS
        let projectReady = exists && hasPubspec
        return projectReady && hasAnyPlatform
    }
}

/// 빌드 한 줄 로그.
public struct BuildLogLine: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let at: Date

    public init(text: String, at: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.at = at
    }
}
