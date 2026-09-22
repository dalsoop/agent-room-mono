import Darwin
import Dispatch
import Foundation
import RoomKit

/// 방 localhost HTTP 프록시. 허용 도메인만 upstream 으로 잇고 나머지는 403 + jsonl.
public final class RoomAllowlistProxy {
    public static let defaultHTTPSPort = 443
    public static let defaultHTTPPort = 80

    public let port: UInt16
    public let allowedDomains: [String]
    public let deniedLogURL: URL

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let serveQueue = DispatchQueue(
        label: "agent-room-terminal.allowlist-proxy.serve",
        attributes: .concurrent
    )
    private let logLock = NSLock()
    private let stopLock = NSLock()
    private var stopped = false
    private let wall: NetworkWall

    public init(port: UInt16, allowedDomains: [String], deniedLogURL: URL) {
        self.port = port
        self.allowedDomains = allowedDomains
        self.deniedLogURL = deniedLogURL
        self.wall = .allow(domains: allowedDomains)
    }

    public static func start(
        allowedDomains: [String],
        deniedLogURL: URL
    ) throws -> RoomAllowlistProxy {
        let created = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard created >= 0 else {
            throw UnixSocketIOError.systemCall("socket", errno)
        }
        var reuse: Int32 = 1
        _ = setsockopt(
            created,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        )
        try UnixSocketIO.configureNoSIGPIPE(created)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = Self.loopbackIPv4
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.bind(created, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(created)
            throw UnixSocketIOError.systemCall("bind", errno)
        }
        guard listen(created, 32) == 0 else {
            Darwin.close(created)
            throw UnixSocketIOError.systemCall("listen", errno)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                getsockname(created, sock, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(created)
            throw UnixSocketIOError.systemCall("getsockname", errno)
        }
        let port = UInt16(bigEndian: bound.sin_port)
        let proxy = RoomAllowlistProxy(
            port: port,
            allowedDomains: allowedDomains,
            deniedLogURL: deniedLogURL
        )
        proxy.listenFD = created
        try proxy.ensureDeniedLog()
        let source = DispatchSource.makeReadSource(
            fileDescriptor: created,
            queue: DispatchQueue(label: "agent-room-terminal.allowlist-proxy.accept")
        )
        source.setEventHandler { [weak proxy] in
            proxy?.acceptOne()
        }
        proxy.acceptSource = source
        source.resume()
        return proxy
    }

    public func stop() {
        stopLock.lock()
        let already = stopped
        stopped = true
        stopLock.unlock()
        guard !already else { return }
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
    }

    public static func parseTarget(from request: Data) -> (host: String, port: Int, isConnect: Bool)? {
        guard let text = String(data: request, encoding: .utf8) else { return nil }
        let head = text.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = head.first else { return nil }
        let parts = first.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let rest = head.count > 1 ? String(head[1]) : ""
        if method == "CONNECT" {
            return splitHostPort(target, defaultPort: defaultHTTPSPort, isConnect: true)
        }
        if let url = URL(string: target), let host = url.host, !host.isEmpty {
            let port = url.port ?? (url.scheme == "https" ? 443 : 80)
            return (host, port, false)
        }
        if let hostLine = headerValue("Host", in: rest) {
            return splitHostPort(hostLine, defaultPort: defaultHTTPPort, isConnect: false)
        }
        return nil
    }

    private func acceptOne() {
        stopLock.lock()
        let done = stopped
        let fd = listenFD
        stopLock.unlock()
        if done || fd < 0 { return }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        try? UnixSocketIO.configureNoSIGPIPE(client)
        serveQueue.async { [weak self] in
            self?.serve(client: client)
        }
    }

    private func serve(client: Int32) {
        defer { Darwin.close(client) }
        do {
            let header = try readHeaders(fd: client)
            guard let target = Self.parseTarget(from: header) else {
                try writeHTTP(fd: client, status: 400, reason: "Bad Request")
                return
            }
            guard wall.allows(host: target.host) else {
                appendDenied(host: target.host, port: target.port)
                try writeHTTP(fd: client, status: 403, reason: "Forbidden")
                return
            }
            let upstream = try connectUpstream(host: target.host, port: target.port)
            defer {
                Darwin.close(upstream)
            }
            if target.isConnect {
                try UnixSocketIO.writeAll(
                    fd: client,
                    data: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
                )
            } else {
                try UnixSocketIO.writeAll(fd: upstream, data: header)
            }
            splice(client: client, upstream: upstream)
        } catch {
            return
        }
    }

    private func readHeaders(fd: Int32) throws -> Data {
        var collected = Data()
        let marker = Data("\r\n\r\n".utf8)
        while collected.count < 65_536 {
            let chunk = try UnixSocketIO.readSome(fd: fd, max: 4096)
            if chunk.isEmpty { continue }
            collected.append(chunk)
            if let range = collected.range(of: marker) {
                return Data(collected[..<range.upperBound])
            }
        }
        throw UnixSocketIOError.closed
    }

    private func connectUpstream(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        let lookup = host.withCString { hostC in
            String(port).withCString { portC in
                getaddrinfo(hostC, portC, &hints, &info)
            }
        }
        guard lookup == 0, let first = info else {
            throw UnixSocketIOError.systemCall("getaddrinfo", errno)
        }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            let fd = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd >= 0 {
                try? UnixSocketIO.configureNoSIGPIPE(fd)
                let ok = Darwin.connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0
                if ok { return fd }
                Darwin.close(fd)
            }
            cursor = current.pointee.ai_next
        }
        throw UnixSocketIOError.systemCall("connect", errno)
    }

    private func splice(client: Int32, upstream: Int32) {
        let group = DispatchGroup()
        group.enter()
        serveQueue.async {
            Self.pump(from: client, to: upstream)
            group.leave()
        }
        group.enter()
        serveQueue.async {
            Self.pump(from: upstream, to: client)
            group.leave()
        }
        group.wait()
    }

    private static func pump(from: Int32, to: Int32) {
        while true {
            do {
                let chunk = try UnixSocketIO.readSome(fd: from, max: 16 * 1024)
                if chunk.isEmpty { continue }
                try UnixSocketIO.writeAll(fd: to, data: chunk)
            } catch {
                shutdown(to, SHUT_WR)
                return
            }
        }
    }

    private func writeHTTP(fd: Int32, status: Int, reason: String) throws {
        let body = "\(reason)\n"
        let payload = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        try UnixSocketIO.writeAll(fd: fd, data: Data(payload.utf8))
    }

    private func appendDenied(host: String, port: Int) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "{\"ts\":\"\(ts)\",\"host\":\"\(escapeJSON(host))\",\"port\":\(port)}\n"
        logLock.lock()
        defer { logLock.unlock() }
        let data = Data(line.utf8)
        do {
            let handle = try FileHandle(forWritingTo: deniedLogURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            do {
                try data.write(to: deniedLogURL, options: .atomic)
            } catch {
                return
            }
        }
    }

    private func ensureDeniedLog() throws {
        let dir = deniedLogURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: deniedLogURL.path) {
            try Data().write(to: deniedLogURL)
        }
    }

    private func escapeJSON(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static var loopbackIPv4: in_addr {
        in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)
    }

    private static func headerValue(_ name: String, in headers: String) -> String? {
        let want = name.lowercased() + ":"
        for line in headers.split(separator: "\r\n") {
            let text = String(line)
            if text.lowercased().hasPrefix(want) {
                return String(text.dropFirst(want.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func splitHostPort(
        _ raw: String,
        defaultPort: Int,
        isConnect: Bool
    ) -> (host: String, port: Int, isConnect: Bool) {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var port = defaultPort
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
            let inner = String(host[host.index(after: host.startIndex)..<close])
            let rest = host[host.index(after: close)...]
            if rest.hasPrefix(":"), let parsed = Int(rest.dropFirst()) {
                port = parsed
            }
            host = inner
        } else if let colon = host.lastIndex(of: ":"),
                  let parsed = Int(host[host.index(after: colon)...]) {
            port = parsed
            host = String(host[..<colon])
        }
        return (host, port, isConnect)
    }
}

public enum RoomNetworkJSON {
    public static func object(wall: NetworkWall, proxyPort: UInt16?) -> [String: Any] {
        var body: [String: Any] = [
            "mode": wall.modeName,
            "allowedDomains": wall.allowedDomains,
        ]
        if let proxyPort {
            body["proxyPort"] = Int(proxyPort)
        } else {
            body["proxyPort"] = NSNull()
        }
        return body
    }
}
