import Darwin
import Foundation

public enum UnixSocketIOError: Error, Equatable, Sendable {
    case pathTooLong
    case systemCall(String, Int32)
    case closed
}

public enum UnixSocketIO {
    public static func socketAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count + 1 <= capacity else {
            throw UnixSocketIOError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in bytes.enumerated() {
                raw.storeBytes(of: byte, toByteOffset: index, as: UInt8.self)
            }
        }
        return address
    }

    public static func configureNoSIGPIPE(_ fd: Int32) throws {
        var value: Int32 = 1
        let result = setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &value,
            socklen_t(MemoryLayout<Int32>.size)
        )
        guard result == 0 else {
            throw UnixSocketIOError.systemCall("setsockopt", errno)
        }
    }

    public static func writeAll(fd: Int32, data: Data) throws {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), remaining)
            }
            if written > 0 {
                offset += written
                continue
            }
            if written < 0 && errno == EINTR {
                continue
            }
            throw UnixSocketIOError.systemCall("write", errno)
        }
    }

    public static func readSome(fd: Int32, max: Int = 64 * 1024) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: max)
        let count = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(fd, raw.baseAddress, raw.count)
        }
        if count > 0 {
            return Data(buffer[0..<count])
        }
        if count == 0 {
            throw UnixSocketIOError.closed
        }
        if errno == EINTR {
            return Data()
        }
        throw UnixSocketIOError.systemCall("read", errno)
    }

    public static func readFrame(fd: Int32) throws -> Data {
        var decoder = DaemonFrameDecoder()
        while true {
            let chunk = try readSome(fd: fd)
            if chunk.isEmpty { continue }
            let frames = try decoder.append(chunk)
            if let first = frames.first {
                return first
            }
        }
    }

    /// 소켓 연결의 수명 동안 디코더 상태와 대기 중인 프레임을 보존하는 연속 스트림 리더.
    /// 단일 TCP/유닉스 패킷에 복수 프레임이 도착해도 후속 프레임 유실을 방지한다.
    public final class SocketStream {
        public let fd: Int32
        private var decoder = DaemonFrameDecoder()
        private var pendingFrames: [Data] = []

        public init(fd: Int32) {
            self.fd = fd
        }

        public func readFrame() throws -> Data {
            while pendingFrames.isEmpty {
                let chunk = try UnixSocketIO.readSome(fd: fd)
                if chunk.isEmpty { continue }
                let frames = try decoder.append(chunk)
                pendingFrames.append(contentsOf: frames)
            }
            return pendingFrames.removeFirst()
        }
    }
}

