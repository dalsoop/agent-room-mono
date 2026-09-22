import Foundation

/// Daemon-owned log (not a room `state/` file). Path comes from `AppPaths`.
public enum DaemonLog {
    public static func append(_ message: String, to url: URL?) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        guard let url else {
            fputs(line, stderr)
            return
        }
        guard let data = line.data(using: .utf8) else {
            fputs("daemon-log-encode-failed: \(message)\n", stderr)
            return
        }
        do {
            try write(data, to: url)
        } catch {
            fputs("daemon-log-write-failed: \(error)\n", stderr)
            fputs(line, stderr)
        }
    }

    public static func describe(_ error: Error) -> String {
        if let frame = error as? DaemonFrameError {
            switch frame {
            case .zeroLengthFrame:
                return "zeroLengthFrame"
            case .frameTooLarge:
                return "frameTooLarge"
            case .truncated:
                return "truncated"
            }
        }
        if let socket = error as? UnixSocketIOError {
            switch socket {
            case .closed:
                return "closed"
            case .pathTooLong:
                return "pathTooLong"
            case .systemCall(let name, let code):
                return "\(name):\(code)"
            }
        }
        if error is DecodingError {
            return "invalidJSON"
        }
        if let protocolError = error as? DaemonProtocolError {
            switch protocolError {
            case .requestFailed(let message):
                return message
            case .unexpectedFrame:
                return "unexpectedFrame"
            }
        }
        return String(describing: error)
    }

    private static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager()
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fm.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try handle.close()
            throw error
        }
    }
}