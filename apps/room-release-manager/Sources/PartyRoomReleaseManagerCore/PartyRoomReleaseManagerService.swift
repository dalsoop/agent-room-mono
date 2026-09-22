import InteropKit
import LocalizationKit
import Foundation
import CommandKit
import AppPathsKit

/// 파티룸 멀티 플랫폼 배포 매니저 도메인 로직.
/// 빌드 명령 실행, 산출물 스캔, 설정 저장, GitHub 힌트를 담당한다.
public struct PartyRoomReleaseManagerService: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    private var fm: FileManager { .default }

    // MARK: - Config

    public func loadConfig() -> PartyRoomReleaseConfig {
        let url = PartyRoomReleaseConfig.storeURL
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PartyRoomReleaseConfig.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return PartyRoomReleaseConfig()
        } catch {
            fputs(
                "PartyRoomReleaseManager: config load failed: \(error.localizedDescription)\n",
                stderr
            )
            return PartyRoomReleaseConfig()
        }
    }

    public func saveConfig(_ config: PartyRoomReleaseConfig) throws {
        let url = PartyRoomReleaseConfig.storeURL
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Probe

    public func probe(config: PartyRoomReleaseConfig? = nil) async -> ProjectProbe {
        let cfg = config ?? loadConfig()
        let root = cfg.projectPath
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: root, isDirectory: &isDir) && isDir.boolValue
        let pubspec = (root as NSString).appendingPathComponent(PartyRoomBuildLayout.pubspec)
        let releaseSh = (root as NSString).appendingPathComponent(PartyRoomBuildLayout.releaseScript)
        let hasPubspec = fm.isReadableFile(atPath: pubspec)
        let hasRelease = fm.isReadableFile(atPath: releaseSh)
        let hasAndroid = dirExists(root, PartyRoomBuildLayout.androidDir)
        let hasMac = dirExists(root, PartyRoomBuildLayout.macosDir)
        let hasWin = dirExists(root, PartyRoomBuildLayout.windowsDir)
        let hasIOS = dirExists(root, PartyRoomBuildLayout.iosDir)
        let hasFlutterBin = await commandExists(PartyRoomHostTools.flutter)
        let hasFvm = await commandExists(PartyRoomHostTools.fvm)
        let flutter = hasFlutterBin || hasFvm
        let gh = await commandExists("gh")

        let artifacts = PartyRoomPlatform.allCases.map { platform in
            artifactStatus(root: root, platform: platform)
        }

        let readyCount = artifacts.filter(\.ready).count
        let summary: String
        if !exists {
            summary = "프로젝트 경로 없음"
        } else if !hasPubspec {
            summary = "pubspec.yaml 없음"
        } else {
            summary = CLILocalization.format("PartyRoomReleaseManagerService.string",  [hasAndroid, hasMac, hasWin, hasIOS].filter { $0 }.count , readyCount, flutter ? "OK" : CLILocalization.string("common.none"))
        }

        return ProjectProbe(
            projectPath: root,
            exists: exists,
            hasPubspec: hasPubspec,
            hasReleaseScript: hasRelease,
            hasAndroid: hasAndroid,
            hasMacOS: hasMac,
            hasWindows: hasWin,
            hasIOS: hasIOS,
            flutterOnPath: flutter,
            ghOnPath: gh,
            artifacts: artifacts,
            summaryLine: summary
        )
    }

    // MARK: - Build

    /// 플랫폼 빌드. 완료 후 (exitCode, 합친 로그) 반환.
    public func build(
        platform: PartyRoomPlatform,
        config: PartyRoomReleaseConfig? = nil
    ) async -> (ok: Bool, log: String) {
        let cfg = config ?? loadConfig()
        let root = cfg.projectPath
        guard fm.fileExists(atPath: root) else {
            return (false, "error: project path missing: \(root)")
        }

        let flutter = await resolveFlutter()
        guard let flutter else {
            return (false, "error: flutter/fvm not on PATH")
        }

        var log = "▶ flutter pub get\n"
        let get = await runner.run(flutter, ["pub", "get"], cwd: root)
        log += get.stdout + get.stderr
        if !get.ok {
            return (false, log + "\npub get failed (\(get.exitCode))")
        }

        switch platform {
        case .android:
            log += "\n▶ flutter build apk --release\n"
            let r = await runner.run(flutter, ["build", "apk", "--release"], cwd: root)
            log += r.stdout + r.stderr
            return (r.ok, log)
        case .macos:
            // 배포판은 release.sh (서명·공증·DMG). 개발용은 build macos 만.
            let releaseSh = (root as NSString).appendingPathComponent(PartyRoomBuildLayout.releaseScript)
            if fm.isExecutableFile(atPath: releaseSh) || fm.isReadableFile(atPath: releaseSh) {
                log += CLILocalization.format("PartyRoomReleaseManagerService.string-2", PartyRoomBuildLayout.releaseScript)
                let r = ShellCommand.run("bash \(shellQuote(releaseSh))", cwd: root)
                log += r.stdout + r.stderr
                return (r.ok, log)
            }
            log += "\n▶ flutter build macos --release\n"
            let r = await runner.run(flutter, ["build", "macos", "--release"], cwd: root)
            log += r.stdout + r.stderr
            return (r.ok, log)
        case .windows:
            log += "\n▶ flutter build windows --release\n"
            log += "(이 Mac에서는 실패할 수 있음 — Windows 호스트 또는 GH Actions 권장)\n"
            let r = await runner.run(flutter, ["build", "windows", "--release"], cwd: root)
            log += r.stdout + r.stderr
            return (r.ok, log)
        case .ios:
            log += "\n▶ flutter build ipa --release\n"
            log += "(서명·Team 필요. 배포는 TestFlight 권장)\n"
            let r = await runner.run(flutter, ["build", "ipa", "--release"], cwd: root)
            log += r.stdout + r.stderr
            return (r.ok, log)
        }
    }

    /// GitHub Release 생성 힌트 명령 문자열 (실행은 사용자/CLI).
    public func githubReleaseHint(config: PartyRoomReleaseConfig? = nil, tag: String? = nil) -> String {
        let cfg = config ?? loadConfig()
        let t = tag ?? "v\(cfg.versionHint)"
        return """
        # 산출물 모은 뒤:
        gh release create \(t) \\
          ./PartyRoom-android.apk \\
          ./PartyRoom-macos.dmg \\
          ./PartyRoom-windows.zip \\
          --repo \(cfg.githubRepo) \\
          --title "Party Room \(t)" \\
          --notes "Android APK · macOS DMG · Windows zip. iOS는 TestFlight."
        """
    }

    public func openProject(config: PartyRoomReleaseConfig? = nil) async {
        let cfg = config ?? loadConfig()
        _ = await runner.run(PartyRoomHostTools.open, [cfg.projectPath])
    }

    public func openArtifactsFolder(config: PartyRoomReleaseConfig? = nil) async {
        let cfg = config ?? loadConfig()
        let candidates = [
            PartyRoomBuildLayout.buildReleaseDir,
            PartyRoomBuildLayout.flutterApkDir,
            PartyRoomBuildLayout.buildDir,
        ].map { (cfg.projectPath as NSString).appendingPathComponent($0) }
        for p in candidates where fm.fileExists(atPath: p) {
            _ = await runner.run(PartyRoomHostTools.open, [p])
            return
        }
        _ = await runner.run(PartyRoomHostTools.open, [cfg.projectPath])
    }

    // MARK: - Private

    private func dirExists(_ root: String, _ name: String) -> Bool {
        var isDir: ObjCBool = false
        let p = (root as NSString).appendingPathComponent(name)
        return fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
    }

    private func commandExists(_ name: String) async -> Bool {
        let r = await runner.run(PartyRoomHostTools.which, [name])
        return r.ok && !r.trimmedStdout.isEmpty
    }

    private func resolveFlutter() async -> String? {
        let whichFlutter = await runner.run(PartyRoomHostTools.which, [PartyRoomHostTools.flutter])
        if whichFlutter.ok, !whichFlutter.trimmedStdout.isEmpty {
            return whichFlutter.trimmedStdout
        }
        let whichFvm = await runner.run(PartyRoomHostTools.which, [PartyRoomHostTools.fvm])
        if whichFvm.ok, !whichFvm.trimmedStdout.isEmpty {
            // fvm flutter ...
            return whichFvm.trimmedStdout
        }
        // common brew path
        let brew = HostPlatform.cliBinPath(PartyRoomHostTools.flutter)
        if fm.isExecutableFile(atPath: brew) { return brew }
        return nil
    }

    private func artifactStatus(root: String, platform: PartyRoomPlatform) -> PlatformArtifactStatus {
        for (rel, note) in platform.artifactCandidates {
            let full = (root as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: full) {
                return PlatformArtifactStatus(platform: platform, ready: true, path: full, note: note)
            }
        }
        return PlatformArtifactStatus(
            platform: platform,
            ready: false,
            path: nil,
            note: platform.missingArtifactHint
        )
    }

    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: DurableAppLayout.sqliteURL(slug: "party-room-release-manager"))
    }
}

// MARK: - CommandRunning cwd helper

private extension CommandRunning {
    func run(_ exe: String, _ args: [String], cwd: String) async -> CommandResult {
        // ProcessCommandRunner 표준 API 가 cwd 를 안 받을 수 있어 env+bash -lc 로 고정.
        let quotedArgs = args.map { shellQuote($0) }.joined(separator: " ")
        let cmd = "cd \(shellQuote(cwd)) && \(shellQuote(exe)) \(quotedArgs)"
        // fvm 이면 `fvm flutter ...`
        if exe.hasSuffix("/\(PartyRoomHostTools.fvm)")
            || (exe as NSString).lastPathComponent == PartyRoomHostTools.fvm {
            let flutterArgs = ([PartyRoomHostTools.flutter] + args).map { shellQuote($0) }.joined(separator: " ")
            let fvmCmd = "cd \(shellQuote(cwd)) && \(shellQuote(exe)) \(flutterArgs)"
            return ShellCommand.run(fvmCmd)
        }
        return ShellCommand.run(cmd)
    }
}

private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
