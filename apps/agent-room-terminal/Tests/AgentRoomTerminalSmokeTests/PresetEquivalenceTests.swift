import XCTest
import Foundation
import InteropKit
@testable import RoomKit

/// 프리셋 동등성 통합 테스트.
///
/// readOnly·toolbelt·open 프리셋마다 seatbelt 백엔드와 srt 백엔드에서
/// 같은 프로브 명령 집합을 돌려 허용/거부 결과를 비교한다.
/// srt 가 미설치된 환경에서는 skip 한다.
final class PresetEquivalenceTests: XCTestCase {
    private let home = NSHomeDirectory()
    private let srtBinary: String? = {
        let candidates = ["\(HostPlatform.homebrewBin)/srt", "/usr/local/bin/srt"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    struct ProbeResult: CustomStringConvertible {
        var name: String
        var seatbeltAllowed: Bool
        var srtAllowed: Bool
        var match: Bool { seatbeltAllowed == srtAllowed }
        var description: String {
            let sb = seatbeltAllowed ? "allow" : "deny"
            let sr = srtAllowed ? "allow" : "deny"
            let tag = match ? "✓" : "✗"
            return "\(tag) \(name): seatbelt=\(sb) srt=\(sr)"
        }
    }

    func testPresetEquivalence() throws {
        guard let srt = srtBinary else {
            throw XCTSkip("srt binary not installed — skipping equivalence test")
        }
        let tmpBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("preset-equiv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpBase) }

        let presets: [RoomWallPreset] = [.readOnly, .toolbelt, .open]
        var allResults: [String: [ProbeResult]] = [:]

        for preset in presets {
            let roomDir = tmpBase.appendingPathComponent("room-\(preset.rawValue)", isDirectory: true).path
            try FileManager.default.createDirectory(atPath: roomDir, withIntermediateDirectories: true)
            let workdir = tmpBase.appendingPathComponent("work-\(preset.rawValue)", isDirectory: true).path
            try FileManager.default.createDirectory(atPath: workdir, withIntermediateDirectories: true)

            let walls = RoomWalls.preset(preset)

            // seatbelt profile
            let seatbeltResult = SeatbeltCompiler.compile(
                spec: RoomSpec(
                    tenant: "test", task: "equiv", verdict: "check",
                    workdir: workdir, walls: walls
                ),
                roomDir: roomDir, home: home
            )

            // srt settings
            let srtResult = SRTSettingsRenderer.render(
                walls: walls, workdir: workdir, roomDir: roomDir, home: home
            )
            let settingsPath = try SRTLaunchHelper.writeSettings(srtResult.settingsJSON, roomDir: roomDir)

            // 프로브 명령 집합
            let probes: [(name: String, argv: [String])] = [
                ("workdir_write", ["touch", "\(workdir)/probe-file"]),
                ("home_write", ["touch", "\(home)/.probe-equiv-test"]),
                ("etc_read", ["cat", "/etc/hosts"]),
                ("room_outside_write", ["touch", "/tmp/probe-equiv-outside"]),
            ]

            var results: [ProbeResult] = []
            for (name, argv) in probes {
                let sbOK = runSeatbelt(profile: seatbeltResult.profile, argv: argv, workdir: workdir)
                let srtOK = runSRT(srt: srt, settingsPath: settingsPath, argv: argv, workdir: workdir)
                results.append(ProbeResult(name: name, seatbeltAllowed: sbOK, srtAllowed: srtOK))
            }
            allResults[preset.rawValue] = results
        }

        // 결과 테이블 출력
        print("\n=== Preset Equivalence Results ===")
        for preset in presets {
            print("\n[\(preset.rawValue)]")
            for result in allResults[preset.rawValue] ?? [] {
                print("  \(result)")
            }
        }
        print("=== End ===\n")

        // 차이는 기록만 하고 테스트 실패로 만들지 않는다 (다음 회차 판단 근거)
        var mismatches: [String] = []
        for (preset, results) in allResults {
            for r in results where !r.match {
                mismatches.append("\(preset)/\(r.name)")
            }
        }
        if !mismatches.isEmpty {
            print("Mismatches (expected, for next-round analysis): \(mismatches.joined(separator: ", "))")
        }
    }

    /// --disable-sandbox 중첩 문제 실측
    func testNestedSandboxInSRT() throws {
        guard let srt = srtBinary else {
            throw XCTSkip("srt binary not installed")
        }
        let tmpBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("nested-sb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpBase) }

        let roomDir = tmpBase.appendingPathComponent("room", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: roomDir, withIntermediateDirectories: true)

        let walls = RoomWalls.preset(.open)
        let result = SRTSettingsRenderer.render(
            walls: walls, workdir: roomDir, roomDir: roomDir, home: home
        )
        let settingsPath = try SRTLaunchHelper.writeSettings(result.settingsJSON, roomDir: roomDir)

        // SwiftPM sandbox-exec 중첩 시뮬레이션
        let nestedAllowed = runSRT(
            srt: srt,
            settingsPath: settingsPath,
            argv: ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)", "/usr/bin/true"],
            workdir: roomDir
        )

        print("\n=== --disable-sandbox nesting in srt ===")
        print("sandbox-exec inside srt: \(nestedAllowed ? "allowed" : "denied")")
        print("=== End ===\n")
    }

    // MARK: - Helpers

    private func runSeatbelt(profile: String, argv: [String], workdir: String) -> Bool {
        let sandbox = "/usr/bin/sandbox-exec"
        guard FileManager.default.isExecutableFile(atPath: sandbox) else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sandbox)
        proc.arguments = ["-p", profile] + argv
        proc.currentDirectoryURL = URL(fileURLWithPath: workdir)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runSRT(srt: String, settingsPath: String, argv: [String], workdir: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: srt)
        proc.arguments = ["--settings", settingsPath] + argv
        proc.currentDirectoryURL = URL(fileURLWithPath: workdir)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// 스모크 테스트용 SRTLaunch 헬퍼 (데몬 의존 없이 설정 파일 쓰기)
enum SRTLaunchHelper {
    static func writeSettings(_ json: String, roomDir: String) throws -> String {
        let url = URL(fileURLWithPath: roomDir)
            .appendingPathComponent("srt-settings.json", isDirectory: false)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
