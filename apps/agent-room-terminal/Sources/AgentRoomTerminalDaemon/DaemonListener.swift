import Darwin
import Foundation
import AgentRoomTerminalCore

final class DaemonListener {
    let socketURL: URL
    private var fd: Int32 = -1

    init(socketURL: URL) {
        self.socketURL = socketURL
    }

    var fileDescriptor: Int32 { fd }

    func bindAndListen() throws {
        let fm = FileManager.default
        let directory = socketURL.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.setAttributes(
            [.posixPermissions: NSNumber(value: DaemonDefaults.socketDirectoryMode)],
            ofItemAtPath: directory.path
        )
        try removeStaleSocket()
        let created = socket(AF_UNIX, SOCK_STREAM, 0)
        guard created >= 0 else {
            throw UnixSocketIOError.systemCall("socket", errno)
        }
        fd = created
        do {
            try UnixSocketIO.configureNoSIGPIPE(fd)
            try bindSocket()
            guard listen(fd, 16) == 0 else {
                throw UnixSocketIOError.systemCall("listen", errno)
            }
            guard chmod(socketURL.path, mode_t(DaemonDefaults.socketFileMode)) == 0 else {
                throw UnixSocketIOError.systemCall("chmod", errno)
            }
        } catch {
            Darwin.close(fd)
            fd = -1
            throw error
        }
    }

    func acceptClient() throws -> Int32 {
        let client = accept(fd, nil, nil)
        guard client >= 0 else {
            throw UnixSocketIOError.systemCall("accept", errno)
        }
        try UnixSocketIO.configureNoSIGPIPE(client)
        return client
    }

    func rebind() throws {
        close()
        try bindAndListen()
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        unlink(socketURL.path)
    }

    private func removeStaleSocket() throws {
        let result = unlink(socketURL.path)
        if result == 0 { return }
        if errno == ENOENT { return }
        throw UnixSocketIOError.systemCall("unlink", errno)
    }

    private func bindSocket() throws {
        var address = try UnixSocketIO.socketAddress(path: socketURL.path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.bind(fd, sock, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            throw UnixSocketIOError.systemCall("bind", errno)
        }
    }
}
