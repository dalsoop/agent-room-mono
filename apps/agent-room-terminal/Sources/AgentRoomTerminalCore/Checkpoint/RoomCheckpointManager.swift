import Foundation

/// 방의 `work/` 작업 디렉토리를 체크포인트로 보존하고 롤백을 수행하는 매니저.
public final class RoomCheckpointManager: Sendable {
    public static let shared = RoomCheckpointManager()

    public init() {}

    /// 방 내 checkpoints 폴더 위치: `<roomURL>/checkpoints/`
    public func checkpointsDirectory(in roomURL: URL) -> URL {
        roomURL.appendingPathComponent("checkpoints", isDirectory: true)
    }

    /// 방 `work/` 폴더 위치: `<roomURL>/work/`
    public func workDirectory(in roomURL: URL) -> URL {
        roomURL.appendingPathComponent("work", isDirectory: true)
    }

    /// `work/` 디렉토리의 현재 상태를 체크포인트로 저장한다.
    @discardableResult
    public func createCheckpoint(
        roomURL: URL,
        checkpointID: String? = nil,
        description: String? = nil
    ) throws -> RoomCheckpoint {
        let fm = FileManager()
        let workURL = workDirectory(in: roomURL).resolvingSymlinksInPath()

        if !fm.fileExists(atPath: workURL.path) {
            try fm.createDirectory(at: workURL, withIntermediateDirectories: true)
        }

        let id = checkpointID ?? "ckpt-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
        let ckptDir = checkpointsDirectory(in: roomURL).appendingPathComponent(id, isDirectory: true).resolvingSymlinksInPath()
        let snapshotDir = ckptDir.appendingPathComponent("snapshot", isDirectory: true)

        if fm.fileExists(atPath: ckptDir.path) {
            try fm.removeItem(at: ckptDir)
        }
        try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        let (manifest, totalSize) = try copyWorkFilesToSnapshot(workURL: workURL, snapshotDir: snapshotDir, fileManager: fm)

        let checkpoint = RoomCheckpoint(
            id: id,
            roomID: roomURL.lastPathComponent,
            createdAt: Date(),
            fileCount: manifest.count,
            totalSizeBytes: totalSize,
            manifest: manifest,
            description: description
        )

        let metaURL = ckptDir.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(checkpoint)
        try data.write(to: metaURL, options: .atomic)

        return checkpoint
    }

    private func copyWorkFilesToSnapshot(
        workURL: URL,
        snapshotDir: URL,
        fileManager fm: FileManager
    ) throws -> (manifest: [String: CheckpointFileEntry], totalSize: Int64) {
        var manifest: [String: CheckpointFileEntry] = [:]
        var totalSize: Int64 = 0

        let enumerator = fm.enumerator(
            at: workURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        )

        let resolvedWorkURL = workURL.resolvingSymlinksInPath()
        let workPathPrefix = resolvedWorkURL.path.hasSuffix("/") ? resolvedWorkURL.path : resolvedWorkURL.path + "/"

        while let fileURL = enumerator?.nextObject() as? URL {
            let resolvedURL = fileURL.resolvingSymlinksInPath()
            let path = resolvedURL.path
            guard path.hasPrefix(workPathPrefix) else { continue }
            let rel = String(path.dropFirst(workPathPrefix.count))

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let targetURL = snapshotDir.appendingPathComponent(rel)
            if isDir.boolValue {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: targetURL)

                var size: Int64 = 0
                var mtime = Date().timeIntervalSince1970
                do {
                    let attrs = try fm.attributesOfItem(atPath: path)
                    size = (attrs[.size] as? Int64) ?? 0
                    mtime = ((attrs[.modificationDate] as? Date) ?? Date()).timeIntervalSince1970
                } catch {
                    FileHandle.standardError.write(Data("attributesOfItem error: \(error)\n".utf8))
                }
                totalSize += size
                manifest[rel] = CheckpointFileEntry(relativePath: rel, sizeBytes: size, modifiedTimestamp: mtime)
            }
        }

        return (manifest, totalSize)
    }

    /// `work/` 작업 디렉토리를 지정된 체크포인트 상태로 롤백(되돌림)한다.
    public func rollback(roomURL: URL, to checkpointID: String) throws {
        let fm = FileManager()
        let ckptDir = checkpointsDirectory(in: roomURL).appendingPathComponent(checkpointID, isDirectory: true).resolvingSymlinksInPath()
        let snapshotDir = ckptDir.appendingPathComponent("snapshot", isDirectory: true)

        guard fm.fileExists(atPath: snapshotDir.path) else {
            throw CheckpointError.checkpointNotFound(id: checkpointID)
        }

        let workURL = workDirectory(in: roomURL).resolvingSymlinksInPath()
        try resetWorkDirectory(workURL: workURL, fileManager: fm)
        try restoreSnapshotFiles(from: snapshotDir, to: workURL, fileManager: fm)
    }

    private func resetWorkDirectory(workURL: URL, fileManager fm: FileManager) throws {
        if fm.fileExists(atPath: workURL.path) {
            let contents = try fm.contentsOfDirectory(at: workURL, includingPropertiesForKeys: nil)
            for item in contents {
                try fm.removeItem(at: item)
            }
        } else {
            try fm.createDirectory(at: workURL, withIntermediateDirectories: true)
        }
    }

    private func restoreSnapshotFiles(from snapshotDir: URL, to workURL: URL, fileManager fm: FileManager) throws {
        let resolvedSnapshotURL = snapshotDir.resolvingSymlinksInPath()
        let snapshotPrefix = resolvedSnapshotURL.path.hasSuffix("/") ? resolvedSnapshotURL.path : resolvedSnapshotURL.path + "/"
        let enumerator = fm.enumerator(
            at: snapshotDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let resolvedURL = fileURL.resolvingSymlinksInPath()
            let path = resolvedURL.path
            guard path.hasPrefix(snapshotPrefix) else { continue }
            let rel = String(path.dropFirst(snapshotPrefix.count))

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let targetURL = workURL.appendingPathComponent(rel)
            if isDir.boolValue {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: targetURL)
            }
        }
    }

    /// 방의 모든 체크포인트 목록을 최신순으로 반환한다.
    public func listCheckpoints(roomURL: URL) throws -> [RoomCheckpoint] {
        let fm = FileManager()
        let ckptsDir = checkpointsDirectory(in: roomURL)
        guard fm.fileExists(atPath: ckptsDir.path) else { return [] }

        let subdirs = try fm.contentsOfDirectory(at: ckptsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var results: [RoomCheckpoint] = []
        let decoder = JSONDecoder()

        for dir in subdirs {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL) else { continue }
            do {
                let ckpt = try decoder.decode(RoomCheckpoint.self, from: data)
                results.append(ckpt)
            } catch {
                continue
            }
        }

        return results.sorted { $0.createdAt > $1.createdAt }
    }

    /// 최신 체크포인트를 반환한다.
    public func latestCheckpoint(roomURL: URL) throws -> RoomCheckpoint? {
        try listCheckpoints(roomURL: roomURL).first
    }
}

public enum CheckpointError: LocalizedError, Equatable {
    case checkpointNotFound(id: String)
    case workDirectoryMissing

    public var errorDescription: String? {
        switch self {
        case .checkpointNotFound(let id):
            return "Checkpoint not found: \(id)"
        case .workDirectoryMissing:
            return "Work directory is missing"
        }
    }
}
