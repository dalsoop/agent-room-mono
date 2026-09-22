import Foundation

/// 방 `work/` 디렉토리의 파일 메타데이터 항목.
public struct CheckpointFileEntry: Codable, Equatable, Sendable {
    public var relativePath: String
    public var sizeBytes: Int64
    public var modifiedTimestamp: Double

    public init(relativePath: String, sizeBytes: Int64, modifiedTimestamp: Double) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedTimestamp = modifiedTimestamp
    }
}

/// 방 `work/` 작업 폴더의 체크포인트 스냅샷 메타데이터.
public struct RoomCheckpoint: Codable, Equatable, Sendable {
    public var id: String
    public var roomID: String
    public var createdAt: Date
    public var fileCount: Int
    public var totalSizeBytes: Int64
    public var manifest: [String: CheckpointFileEntry]
    public var description: String?

    public init(
        id: String,
        roomID: String,
        createdAt: Date = Date(),
        fileCount: Int = 0,
        totalSizeBytes: Int64 = 0,
        manifest: [String: CheckpointFileEntry] = [:],
        description: String? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.createdAt = createdAt
        self.fileCount = fileCount
        self.totalSizeBytes = totalSizeBytes
        self.manifest = manifest
        self.description = description
    }
}
