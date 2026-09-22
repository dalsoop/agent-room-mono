import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("DaemonExecutable — PATH 호출에서도 옆자리 데몬을 찾는다")
struct DaemonExecutableLocateTests {
    @Test("argv[0] 에 디렉터리가 없으면 PATH 에서 CLI 위치를 찾아 그 옆을 본다")
    func locatesViaPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-daemon-locate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cli = dir.appendingPathComponent("agent-room-terminal")
        let daemon = dir.appendingPathComponent(DaemonExecutable.fileName)
        for file in [cli, daemon] {
            try Data("#!/bin/sh\n".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: file.path
            )
        }
        let found = DaemonExecutable.locate(
            environment: ["PATH": dir.path + ":/usr/bin"],
            arguments: ["agent-room-terminal"]
        )
        #expect(found?.path == daemon.path)
    }

    @Test("환경 변수 override 가 가장 먼저다")
    func environmentOverrideWins() {
        let found = DaemonExecutable.locate(
            environment: [DaemonExecutable.pathEnvironmentKey: "/opt/x/agent-room-terminal-daemon"],
            arguments: ["agent-room-terminal"]
        )
        #expect(found?.path == "/opt/x/agent-room-terminal-daemon")
    }
}
