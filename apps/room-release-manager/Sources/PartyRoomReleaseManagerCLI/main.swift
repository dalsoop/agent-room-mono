import SingleInstanceKit
import StateRootKit
import Foundation
import InteropKit
import PartyRoomReleaseManagerCore
import AppScaffoldKit
import AppPathsKit
import LocalizationKit
import CommandKit

SingleInstanceCLI.autoGuard()

// Cloud Apps 게이트 — GUI 의 `.gujoManaged()` 와 대칭인 CLI 진입 한 줄.
// import 직후라 **무엇보다 먼저** 돈다. help·version·capabilities 와
// 판정 실패는 통과한다(절차: swiftkit-appscaffold/Documentation/gujo-managed.md).
// **동기** 판이다 — await 를 넣으면 이 파일이 async 컨텍스트가 되고
// Thread.sleep 같은 noasync API 를 쓰던 앱이 컴파일에서 죽는다.
GujoManaged.exitIfNotEntitledSync()

// party-room-release-manager — Foundation-only Helpers CLI.

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"
let service = PartyRoomReleaseManagerService()
HealthPulse.publish(app: "party-room-release-manager", status: "cli")

func usage() {
    print(
        """
        party-room-release-manager — 파티룸 멀티 플랫폼 배포 매니저

        Commands:
          status                    소스 트리·산출물 요약
          probe --json              기계 파싱 프로브
          build <android|macos|windows|ios>
          release-hint              GitHub Release 명령 힌트
          open-project              소스 폴더 Finder
          open-artifacts            빌드 산출물 폴더
          config path <dir>         프로젝트 경로 저장
          config repo <owner/name>  GitHub 저장소 저장
          capabilities              interop 계약
          version | help | open     버전 / 도움말 / GUI

        예:
          party-room-release-manager status
          party-room-release-manager build android
          party-room-release-manager build macos
        """
    )
}

func die(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(code)
}

switch cmd {
case "help", "-h", "--help":
    usage()

case "version", "-V", "--version":
    print("party-room-release-manager \(CLIMarketingVersion.current())")

case "status":
    let p = awaitMain { await service.probe() }
    print(p.summaryLine)
    print("path: \(p.projectPath)")
    for a in p.artifacts {
        let mark = a.ready ? "✓" : "·"
        print("  \(mark) \(a.platform.displayName): \(a.note)\(a.path.map { " → \($0)" } ?? "")")
    }

case "probe":
    let probeOpts = Set(args.dropFirst())
    let allowedProbe: Set<String> = ["--json", "--help", "-h"]
    if probeOpts.contains("--help") || probeOpts.contains("-h") {
        print("usage: probe [--json]")
        exit(0)
    }
    let unknownProbe = probeOpts.subtracting(allowedProbe)
    if !unknownProbe.isEmpty {
        die("unknown option: \(unknownProbe.sorted().joined(separator: ", "))", code: 64)
    }
    let p = awaitMain { await service.probe() }
    if probeOpts.contains("--json") {
        struct Out: Encodable {
            let path: String
            let healthy: Bool
            let summary: String
            let flutter: Bool
            let gh: Bool
            let artifacts: [String: Bool]
        }
        var arts: [String: Bool] = [:]
        for a in p.artifacts { arts[a.platform.rawValue] = a.ready }
        let o = Out(
            path: p.projectPath, healthy: p.isHealthy, summary: p.summaryLine,
            flutter: p.flutterOnPath, gh: p.ghOnPath, artifacts: arts
        )
        do {
            let data = try JSONEncoder().encode(o)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            die("json encode failed: \(error.localizedDescription)")
        }
    } else {
        print(p.summaryLine)
    }

case "build":
    guard let platArg = args.dropFirst().first,
          let platform = PartyRoomPlatform(rawValue: platArg)
    else {
        die("usage: build <android|macos|windows|ios>", code: 64)
    }
    let result = awaitMain { await service.build(platform: platform) }
    print(result.log)
    exit(result.ok ? 0 : 1)

case "release-hint":
    print(service.githubReleaseHint())

case "open-project":
    awaitMain { await service.openProject() }

case "open-artifacts":
    awaitMain { await service.openArtifactsFolder() }

case "config":
    var cfg = service.loadConfig()
    let sub = args.dropFirst().first ?? ""
    let val = args.dropFirst(2).first ?? ""
    switch sub {
    case "path":
        guard !val.isEmpty else { die("config path <dir>", code: 64) }
        cfg.projectPath = val
        do {
            try service.saveConfig(cfg)
        } catch {
            die("config save failed: \(error.localizedDescription)")
        }
        print("projectPath=\(cfg.projectPath)")
    case "repo":
        guard !val.isEmpty else { die("config repo <owner/name>", code: 64) }
        cfg.githubRepo = val
        do {
            try service.saveConfig(cfg)
        } catch {
            die("config save failed: \(error.localizedDescription)")
        }
        print("githubRepo=\(cfg.githubRepo)")
    default:
        print("projectPath=\(cfg.projectPath)")
        print("githubRepo=\(cfg.githubRepo)")
        print("versionHint=\(cfg.versionHint)")
    }

case "capabilities":
    let caps = InteropKit.Capabilities(
        name: "party-room-release-manager",
        version: CLIMarketingVersion.current(),
        cli: HostPlatform.cliBinPath("party-room-release-manager"),
        commands: [
            .init(name: "status", summary: CLILocalization.string("main.string"), json: false),
            .init(name: "probe", summary: CLILocalization.string("main.string-2"), json: true),
            .init(name: "build", summary: CLILocalization.string("MainWindowView.groupbox-2"), json: false),
            .init(name: "release-hint", summary: CLILocalization.string("main.string-3"), json: false),
            .init(name: "open-project", summary: CLILocalization.string("main.string-4"), json: false),
            .init(name: "open-artifacts", summary: CLILocalization.string("main.string-5"), json: false),
            .init(name: "config", summary: CLILocalization.string("main.string-6"), json: false),
            .init(name: "path", summary: CLILocalization.string("main.string-7"), json: false),
            .init(name: "repo", summary: CLILocalization.string("main.string-8"), json: false),
            .init(name: "capabilities", summary: CLILocalization.string("main.string-9"), json: true),
            .init(name: "help", summary: CLILocalization.string("main.string-10"), json: false),
            .init(name: "version", summary: CLILocalization.string("main.string-11"), json: false),
            .init(name: "open", summary: "GUI", json: false),
        ],
        state: [
                .init(
        path: DurableAppLayout.tildePath(DurableAppLayout.sqliteURL(slug: "party-room-release-manager")),
        what: CLILocalization.string("main.string-12")
    ),
            .init(
                path: "~/.swift-app-state/party-room-release-manager.json",
                what: CLILocalization.string("main.string-13")
            ),
        ],
        health: .init(
            command: "\(HostPlatform.cliBinPath("party-room-release-manager")) status",
            freshness: "~/.swift-app-state/party-room-release-manager.json"
        ),
        depends: [
            .init(
                id: "system.flutter",
                kind: Capabilities.DependencyKind.command,
                ref: "flutter",
                required: false,
                why: CLILocalization.string("MainWindowView.groupbox-2")
            ),
            .init(
                id: "system.gh",
                kind: Capabilities.DependencyKind.command,
                ref: "gh",
                required: false,
                why: "GitHub Release"
            ),
        ]
    )
    let data = try Envelope.ok(caps)
    print(String(data: data, encoding: .utf8) ?? "{}")

case "open":
    let safeResult = SafeProcessRunner.run(
        PartyRoomHostTools.open,
        ["-b", PartyRoomReleaseDefaults.appBundleID]
    )
    } catch {
        die("failed to open GUI: \(error.localizedDescription)")
    }

default:
    FileHandle.standardError.write(Data("unknown command: \(cmd) (try help)\n".utf8))
    usage()
    exit(64)
}

/// CLI 동기 진입점에서 async 서비스 호출. GCD 세마포어 대신 RunLoop.
@discardableResult
func awaitMain<T: Sendable>(_ body: @Sendable @escaping () async -> T) -> T {
    let box = AsyncBox<T>()
    Task {
        box.value = await body()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    CFRunLoopRun()
    return box.value!
}

private final class AsyncBox<T: Sendable>: @unchecked Sendable {
    var value: T!
}
