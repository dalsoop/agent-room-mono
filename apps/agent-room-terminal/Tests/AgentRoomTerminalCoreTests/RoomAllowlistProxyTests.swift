import Darwin
import Foundation
import XCTest
@testable import AgentRoomTerminalCore

final class RoomAllowlistProxyTests: XCTestCase {
    func testAllowedHostForwardsAndDeniedHostLogs403() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxy-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let origin = try LocalOriginServer.start(body: "ok-body")
        defer { origin.stop() }

        let deniedLog = root.appendingPathComponent("network-denied.jsonl")
        let proxy = try RoomAllowlistProxy.start(
            allowedDomains: ["127.0.0.1"],
            deniedLogURL: deniedLog
        )
        defer { proxy.stop() }

        let allowed = try httpThroughProxy(
            proxyPort: proxy.port,
            host: "127.0.0.1",
            port: Int(origin.port),
            path: "/"
        )
        XCTAssertTrue(allowed.contains("ok-body"), allowed)

        let denied = try httpThroughProxy(
            proxyPort: proxy.port,
            host: "evil.example",
            port: 80,
            path: "/"
        )
        XCTAssertTrue(denied.contains("403"), denied)

        let log = try String(contentsOf: deniedLog, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = log.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, log)
        XCTAssertTrue(log.contains("\"host\":\"evil.example\""), log)
        XCTAssertTrue(log.contains("\"port\":80"), log)
    }

    func testSeatbeltProfileIncludesProxyPort() {
        let scheme = RoomOpenPolicy.seatbeltProfile(
            preset: .toolbelt,
            roomPath: "/tmp/room",
            writePaths: [],
            network: .allow(domains: ["github.com"]),
            proxyPort: 18080
        )
        XCTAssertTrue(
            scheme?.contains("(allow network-outbound (remote ip \"localhost:18080\"))") == true,
            scheme ?? ""
        )
    }

    func testGitBypassBlockedUnlessViaAllowlistProxy() throws {
        let sandbox = "/usr/bin/sandbox-exec"
        let git = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: sandbox) else {
            throw XCTSkip("sandbox-exec missing")
        }
        guard FileManager.default.isExecutableFile(atPath: git) else {
            throw XCTSkip("git missing")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-bypass-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let deniedLog = root.appendingPathComponent("state/network-denied.jsonl")
        try FileManager.default.createDirectory(
            at: deniedLog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let proxy = try RoomAllowlistProxy.start(
            allowedDomains: ["github.com"],
            deniedLogURL: deniedLog
        )
        defer { proxy.stop() }

        let profile = try XCTUnwrap(RoomOpenPolicy.seatbeltProfile(
            preset: .toolbelt,
            roomPath: root.path,
            writePaths: [],
            network: .allow(domains: ["github.com"]),
            proxyPort: proxy.port
        ))
        let repo = "https://github.com/octocat/Hello-World.git"
        let bypass = runGit(
            sandbox: sandbox,
            profile: profile,
            git: git,
            repo: repo,
            env: [
                "HOME": root.path,
                "TMPDIR": tmp.path,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_TERMINAL_PROMPT": "0",
            ]
        )
        XCTAssertNotEqual(bypass.exit, 0, "git without proxy must fail under seatbelt: \(bypass.stderr)")

        let viaProxy = runGit(
            sandbox: sandbox,
            profile: profile,
            git: git,
            repo: repo,
            env: [
                "HOME": root.path,
                "TMPDIR": tmp.path,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_TERMINAL_PROMPT": "0",
                "HTTP_PROXY": "http://localhost:\(proxy.port)",
                "HTTPS_PROXY": "http://localhost:\(proxy.port)",
                "ALL_PROXY": "http://localhost:\(proxy.port)",
            ]
        )
        if viaProxy.exit != 0 {
            throw XCTSkip("internet or github unreachable: \(viaProxy.stderr)")
        }
        XCTAssertEqual(viaProxy.exit, 0, viaProxy.stderr)
    }

    private func httpThroughProxy(
        proxyPort: UInt16,
        host: String,
        port: Int,
        path: String
    ) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = proxyPort.bigEndian
        addr.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.connect(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connected, 0)
        let request = "GET http://\(host):\(port)\(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
        try UnixSocketIO.writeAll(fd: fd, data: Data(request.utf8))
        var collected = Data()
        for _ in 0..<32 {
            do {
                let chunk = try UnixSocketIO.readSome(fd: fd, max: 4096)
                collected.append(chunk)
            } catch {
                break
            }
        }
        return String(data: collected, encoding: .utf8) ?? ""
    }

    private func runGit(
        sandbox: String,
        profile: String,
        git: String,
        repo: String,
        env: [String: String]
    ) -> (exit: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sandbox)
        process.arguments = ["-p", profile, git, "ls-remote", repo]
        process.environment = env
        let err = Pipe()
        let out = Pipe()
        process.standardError = err
        process.standardOutput = out
        do {
            try process.run()
        } catch {
            return (127, error.localizedDescription)
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue(label: "room-allowlist-git-wait").async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + 8) == .timedOut {
            process.terminate()
            return (124, "timed out")
        }
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }
}

private final class LocalOriginServer {
    let port: UInt16
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    static func start(body: String) throws -> LocalOriginServer {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw UnixSocketIOError.systemCall("socket", errno) }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.bind(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(fd)
            throw UnixSocketIOError.systemCall("bind", errno)
        }
        guard listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw UnixSocketIOError.systemCall("listen", errno)
        }
        var named = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &named) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                getsockname(fd, sock, &length)
            }
        }
        let server = LocalOriginServer(port: UInt16(bigEndian: named.sin_port))
        server.listenFD = fd
        let payload = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8
        )
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: DispatchQueue(label: "local-origin")
        )
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            DispatchQueue(label: "local-origin-client").async {
                _ = try? UnixSocketIO.readSome(fd: client, max: 4096)
                try? UnixSocketIO.writeAll(fd: client, data: payload)
                Darwin.close(client)
            }
        }
        server.source = source
        source.resume()
        return server
    }

    private init(port: UInt16) {
        self.port = port
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
    }
}
