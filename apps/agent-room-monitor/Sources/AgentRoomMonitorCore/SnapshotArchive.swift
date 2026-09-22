import Foundation

/// 스냅샷 이력 — 비교 모드의 A|B 실데이터. `~/.agent-room-monitor/snapshots/`.
public struct SnapshotArchive: Sendable {
    public let directory: URL
    private let keep: Int

    public init(directory: URL? = nil, keep: Int = 24) {
        // 자기 상태 — 테넌트 컨텍스트가 있으면 `~/.tenants/<t>/.agent-room-monitor/snapshots`.
        self.directory = directory ?? AppPaths.stateSubdirectory(AppPaths.snapshotsDirectoryName)
        self.keep = keep
    }

    /// `FileManager` 는 Sendable 이 아니라 저장하지 않는다 — 조회·생성·삭제뿐이라 기본 인스턴스로 충분하다.
    private var fm: FileManager { .default }

    public struct Record: Codable, Sendable, Identifiable {
        public var id: String
        public var generatedAt: Date
        public var path: String
    }

    public func record(_ snapshot: TwinSnapshot) throws -> URL {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: snapshot.generatedAt)
            .replacingOccurrences(of: ":", with: "")
        let url = directory.appendingPathComponent("\(stamp).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        prune()
        return url
    }

    public func list() -> [URL] {
        // 디렉터리가 아직 없으면 스냅샷을 한 번도 안 찍은 것 — 에러가 아니라 빈 목록이다.
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        } catch {
            CoreDiagnostics.warn("SnapshotArchive: cannot list \(directory.path): \(error.localizedDescription)")
            return []
        }
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func load(url: URL) -> TwinSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(TwinSnapshot.self, from: Data(contentsOf: url))
        } catch {
            CoreDiagnostics.warn("SnapshotArchive: cannot load \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// 가장 최근 두 장. 한 장뿐이면 비교 불가.
    public func latestPair() -> (older: TwinSnapshot, newer: TwinSnapshot)? {
        let urls = list()
        guard urls.count >= 2,
              let older = load(url: urls[urls.count - 2]),
              let newer = load(url: urls[urls.count - 1])
        else { return nil }
        return (older, newer)
    }

    private func prune() {
        let urls = list()
        guard urls.count > keep else { return }
        for extra in urls.prefix(urls.count - keep) {
            do {
                try fm.removeItem(at: extra)
            } catch {
                // 정리 실패는 다음 기록 때 다시 시도된다 — 이유만 남긴다.
                CoreDiagnostics.warn("SnapshotArchive: cannot prune \(extra.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
