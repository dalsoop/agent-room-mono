import Foundation

/// Core 파일 접근. `FileManager.default` 직접 사용 금지 — 이 프로토콜로 주입한다.
public protocol RoomFileIO: Sendable {
    func fileExists(atPath path: String) -> Bool
    func isDirectory(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func createDirectory(at url: URL) throws
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

public struct FoundationRoomFileIO: RoomFileIO, Sendable {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager().fileExists(atPath: path)
    }

    public func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager().fileExists(atPath: path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager().contentsOfDirectory(atPath: path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager().createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try createDirectory(at: url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }
}
