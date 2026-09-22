import Foundation

public struct LineRingBuffer: Sendable {
    public let capacity: Int
    public let spillURL: URL
    private var lines: [String]
    private var pending = ""

    public init(capacity: Int, spillURL: URL) {
        self.capacity = max(1, capacity)
        self.spillURL = spillURL
        self.lines = []
        self.lines.reserveCapacity(self.capacity)
    }

    public var storedLineCount: Int { lines.count }

    public mutating func ingest(_ text: String) throws {
        pending.append(text)
        while let range = pending.range(of: "\n") {
            let line = String(pending[..<range.lowerBound])
            pending.removeSubrange(..<range.upperBound)
            try appendLine(line)
        }
    }

    public mutating func appendLine(_ line: String) throws {
        if lines.count >= capacity {
            let spilled = lines.removeFirst()
            try Self.spill(spilled, to: spillURL)
        }
        lines.append(line)
    }

    public func snapshot(last count: Int) -> [String] {
        var all = lines
        if !pending.isEmpty {
            all.append(pending)
        }
        let n = max(0, count)
        if n >= all.count { return all }
        return Array(all.suffix(n))
    }

    public static func spill(_ line: String, to url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            try handle.close()
            throw error
        }
    }
}
