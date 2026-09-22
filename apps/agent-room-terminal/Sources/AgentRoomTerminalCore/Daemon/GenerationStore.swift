import Foundation

public struct GenerationStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func bump() throws -> UInt64 {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let current = try readCurrent()
        let next = current + 1
        try String(next).write(to: url, atomically: true, encoding: .utf8)
        return next
    }

    public func readCurrent() throws -> UInt64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt64(text) ?? 0
    }
}
