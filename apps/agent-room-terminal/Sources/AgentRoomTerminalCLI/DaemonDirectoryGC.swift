import Darwin
import Foundation
import AgentRoomTerminalCore

enum DaemonDirectoryGC {
    struct StaleReport: Sendable {
        var staleDirectories: [String]
        var activeDirectories: [String]
    }

    static func scan(tmpDir: String = "/tmp") -> StaleReport {
        let fm = FileManager.default
        let items: [String]
        do {
            items = try fm.contentsOfDirectory(atPath: tmpDir)
        } catch {
            return StaleReport(staleDirectories: [], activeDirectories: [])
        }
        var stale: [String] = []
        var active: [String] = []

        for item in items where item.hasPrefix("art-") {
            let dirPath = (tmpDir as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            if isDaemonAlive(dirPath: dirPath) {
                active.append(dirPath)
            } else {
                stale.append(dirPath)
            }
        }
        return StaleReport(staleDirectories: stale.sorted(), activeDirectories: active.sorted())
    }

    static func cleanup(dryRun: Bool = true, tmpDir: String = "/tmp") -> [String] {
        let report = scan(tmpDir: tmpDir)
        guard !dryRun else { return report.staleDirectories }
        let fm = FileManager.default
        var cleaned: [String] = []
        for path in report.staleDirectories {
            do {
                try fm.removeItem(atPath: path)
                cleaned.append(path)
            } catch {
                FileHandle.standardError.write(
                    Data("cleanup failed for \(path): \(error.localizedDescription)\n".utf8)
                )
            }
        }
        return cleaned
    }

    private static func isDaemonAlive(dirPath: String) -> Bool {
        let fm = FileManager.default
        let pidPath = (dirPath as NSString).appendingPathComponent("daemon.pid")
        do {
            let pidStr = try String(contentsOfFile: pidPath, encoding: .utf8)
            if let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if kill(pid, 0) == 0 {
                    return true
                }
                if errno == EPERM {
                    return true
                }
                return false
            }
        } catch {
            DaemonLog.append("read pid failed: \(error.localizedDescription)", to: nil)
        }

        let sockPath = (dirPath as NSString).appendingPathComponent("daemon.sock")
        if fm.fileExists(atPath: sockPath) {
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            if fd >= 0 {
                defer { Darwin.close(fd) }
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
                withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                    sockPath.withCString { cstr in
                        _ = strncpy(ptr, cstr, maxLen - 1)
                    }
                }
                let len = socklen_t(MemoryLayout<sockaddr_un>.size)
                let connected = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        Darwin.connect(fd, sa, len) == 0
                    }
                }
                if connected {
                    return true
                }
            }
        }
        return false
    }
}
