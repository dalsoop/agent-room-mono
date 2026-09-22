import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomCLIVersion — 번들 Info.plist 또는 Packaging, 없으면 dev")
struct RoomCLIVersionTests {
    @Test("Helpers CLI 는 두 단계 위 Contents/Info.plist 를 읽는다")
    func helpersReadsContentsPlist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rcv-helpers-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helpers = root
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try writePlist(root.appendingPathComponent("Contents/Info.plist"), version: "1.0.99")
        let exe = helpers.appendingPathComponent("agent-room-terminal")
        try Data().write(to: exe)
        #expect(RoomCLIVersion.resolve(processPath: exe.path) == "1.0.99")
    }

    @Test("PATH 심링크는 실경로를 풀어 Helpers plist 를 본다")
    func symlinkResolvesToHelpers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rcv-link-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helpers = root
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try writePlist(root.appendingPathComponent("Contents/Info.plist"), version: "2.3.4")
        let exe = helpers.appendingPathComponent("agent-room-terminal")
        try Data().write(to: exe)
        let link = root.appendingPathComponent("bin-link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: exe.path)
        #expect(RoomCLIVersion.resolve(processPath: link.path) == "2.3.4")
    }

    @Test("개발 바이너리는 위로 올라가 Packaging/Info.plist 를 읽는다")
    func walksUpToPackaging() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rcv-pkg-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let debug = root.appendingPathComponent(".build/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: debug, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Packaging", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePlist(root.appendingPathComponent("Packaging/Info.plist"), version: "9.8.7")
        let exe = debug.appendingPathComponent("agent-room-terminal")
        try Data().write(to: exe)
        #expect(RoomCLIVersion.resolve(processPath: exe.path) == "9.8.7")
    }

    @Test("plist 없어도 Versions 파일이 있으면 버전을 읽는다")
    func versionsFileFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rcv-ver-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let debug = root.appendingPathComponent(".build/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: debug, withIntermediateDirectories: true)
        let versionsDir = root.appendingPathComponent("Versions", isDirectory: true)
        try FileManager.default.createDirectory(at: versionsDir, withIntermediateDirectories: true)
        try Data("1.0.58\n".utf8).write(
            to: versionsDir.appendingPathComponent("agent-room-terminal-swift")
        )
        let exe = debug.appendingPathComponent("agent-room-terminal")
        try Data().write(to: exe)
        #expect(RoomCLIVersion.resolve(processPath: exe.path) == "1.0.58")
    }

    @Test("plist 도 Versions 도 없으면 dev")
    func missingPlistIsDev() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rcv-dev-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let exe = root.appendingPathComponent("orphan-cli")
        try Data().write(to: exe)
        #expect(RoomCLIVersion.resolve(processPath: exe.path) == "dev")
    }

    private func writePlist(_ url: URL, version: String) throws {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>\(version)</string>
        </dict>
        </plist>
        """
        try Data(body.utf8).write(to: url)
    }
}
