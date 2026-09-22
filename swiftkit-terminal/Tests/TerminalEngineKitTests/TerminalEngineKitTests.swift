import XCTest
import Foundation
import os
@testable import TerminalEngineKit

final class TerminalEngineKitTests: XCTestCase {
    // MARK: - Factory Selection

    @MainActor
    func testFactoryMockSelection() {
        let launch = TerminalLaunch(cwd: "/tmp", command: ["echo", "hi"])
        let engine = TerminalEngineFactory.make(kind: .mock, launch: launch)
        guard let mock = engine as? MockTerminalEngine else {
            XCTFail("Expected MockTerminalEngine instance")
            return
        }

        engine.startIfNeeded()
        XCTAssertEqual(mock.startCount, 1)

        engine.send(text: "test-input")
        XCTAssertEqual(mock.sentTexts, ["test-input"])

        engine.terminate()
        XCTAssertEqual(mock.terminateCount, 1)
    }

    @MainActor
    func testFactoryCustomRegistration() {
        TerminalEngineFactory.register(.swiftTerm) { _ in
            MockTerminalEngine()
        }
        XCTAssertTrue(TerminalEngineFactory.isRegistered(.swiftTerm))

        let launch = TerminalLaunch(cwd: "/tmp")
        let engine = TerminalEngineFactory.make(kind: .swiftTerm, launch: launch)
        XCTAssertTrue(engine is MockTerminalEngine)
    }

    // MARK: - PaneEnvInjector

    func testWrapInjectsExportsBeforeExec() {
        var box = PaneSandbox(paneId: "w1", homePath: "/tmp/w1")
        box.environment["FOO"] = "bar"
        let wrapped = PaneEnvInjector.wrap(command: ["claude"], shell: "/bin/zsh", sandbox: box)
        XCTAssertEqual(wrapped[0], "/bin/zsh")
        XCTAssertEqual(wrapped[1], "-l")
        XCTAssertEqual(wrapped[2], "-c")
        let script = wrapped[3]
        XCTAssertTrue(script.contains("export FOO='bar'"), script)
        XCTAssertTrue(script.contains("exec 'claude'"), script)
    }

    func testWrapEmptyCommandKeepsInteractiveShell() {
        let box = PaneSandbox(paneId: "shell1", homePath: "/tmp/shell1",
                              environment: ["PANE_ID": "shell1"])
        let wrapped = PaneEnvInjector.wrap(command: [], shell: "/bin/zsh", sandbox: box)
        XCTAssertEqual(Array(wrapped.prefix(3)), ["/bin/zsh", "-l", "-c"])
        XCTAssertTrue(wrapped[3].contains("exec '/bin/zsh' -l"), wrapped[3])
    }

    func testWrapEmptyEnvironmentReturnsDirectCommand() {
        let box = PaneSandbox(paneId: "empty", homePath: "/tmp/empty", environment: [:])
        let wrapped = PaneEnvInjector.wrap(command: [], shell: "/bin/zsh", sandbox: box)
        XCTAssertEqual(wrapped, ["/bin/zsh", "-l"])
    }

    func testMergeEnvOverwritesBase() {
        let box = PaneSandbox(paneId: "m", homePath: "/h",
                              environment: ["A": "1", "PATH": "/sandbox-bin"])
        let merged = PaneEnvInjector.merge(
            base: ["PATH=/usr/bin", "B=2"], sandbox: box)
        XCTAssertTrue(merged.contains("A=1"), "\(merged)")
        XCTAssertTrue(merged.contains("B=2"), "\(merged)")
        XCTAssertTrue(merged.contains("PATH=/sandbox-bin"), "\(merged)")
        XCTAssertFalse(merged.contains("PATH=/usr/bin"))
    }

    // MARK: - TmuxBacking Argv & Pure Logic

    func testTmuxSessionArgsIncludesSandboxExports() {
        var box = PaneSandbox(paneId: "tmux1", homePath: "/tmp/tmux1")
        box.environment["CUSTOM_HOME"] = "/tmp/custom-x"
        let args = TmuxBacking.sessionArgs(
            socket: "test-socket", config: "/c.conf", name: "test-socket/tmux1",
            cwd: "/tmp", command: ["codex"], shell: "/bin/zsh", sandbox: box)
        XCTAssertTrue(args.contains("new-session"))
        let script = args.last!
        XCTAssertTrue(script.contains("CUSTOM_HOME"), script)
    }

    func testTmuxBackingNamesAndHandles() {
        let backing = TmuxBacking(prefix: "test/", socket: "test", configPath: "/tmp/tmux.conf")
        XCTAssertEqual(backing.sessionName("s1"), "test/s1")
        XCTAssertTrue(backing.isOurs("test/s1"))
        XCTAssertFalse(backing.isOurs("other/s1"))

        XCTAssertEqual(TmuxBacking.normalizeHandle("s1", prefix: "test/"), "test/s1")
        XCTAssertEqual(TmuxBacking.normalizeHandle("test/s1", prefix: "test/"), "test/s1")

        let rawNames = "test/1\nother/2\ntest/3\n"
        let parsed = TmuxBacking.parseNames(rawNames, prefix: "test/")
        XCTAssertEqual(parsed, ["test/1", "test/3"])
    }

    func testTmuxCaptureParsing() {
        let output = "line 1\nline 2\n\n\n"
        let lines = TmuxBacking.parseCaptureLines(output)
        XCTAssertEqual(lines, ["line 1", "line 2"])
    }

    // MARK: - TerminalAppearance

    func testTerminalAppearanceDefaultValues() {
        let appearance = TerminalAppearance.default
        XCTAssertEqual(appearance.fontName, "Menlo")
        XCTAssertEqual(appearance.fontSize, 13)
        XCTAssertEqual(appearance.themeID, "system")
        XCTAssertTrue(appearance.macosOptionAsAlt)
    }

    func testTerminalAppearanceCodableAndClamp() throws {
        let ap = TerminalAppearance(fontName: "Menlo", fontSize: 15, themeID: "dark")
        let back = try JSONDecoder().decode(TerminalAppearance.self,
                                            from: JSONEncoder().encode(ap))
        XCTAssertEqual(back, ap)
        XCTAssertEqual(ap.withSize(999).fontSize, TerminalAppearance.maxSize)
        XCTAssertEqual(ap.withSize(1).fontSize, TerminalAppearance.minSize)
    }

    // MARK: - TerminalByteStream

    func testTerminalByteStreamBufferingAndDelivery() {
        let stream = TerminalByteStream()
        let received = OSAllocatedUnfairLock(initialState: [Data]())

        stream.receive(Data("pre-hook".utf8))

        stream.receiveHandler = { data in
            received.withLock { $0.append(data) }
        }

        XCTAssertEqual(received.withLock { $0.count }, 1)
        XCTAssertEqual(String(data: received.withLock { $0[0] }, encoding: .utf8), "pre-hook")

        stream.receive(Data("post-hook".utf8))
        XCTAssertEqual(received.withLock { $0.count }, 2)
        XCTAssertEqual(String(data: received.withLock { $0[1] }, encoding: .utf8), "post-hook")
    }
}
