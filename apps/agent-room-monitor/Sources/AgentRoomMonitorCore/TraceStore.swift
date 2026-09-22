import Foundation
import LocalizationKit

/// 트레이스 수집기 — 요구사항 C.16. `~/.agent-room-monitor/trace/<sessionID>.jsonl`
/// hook 파일과 스냅샷(스킬 호출·미호출·배치 사건)을 같은 스키마로 쌓는다.
public struct TraceStore: Sendable {
    private let root: URL

    public init(root: URL? = nil) {
        // 자기 상태 — 테넌트 컨텍스트가 있으면 `~/.tenants/<t>/.agent-room-monitor/trace`.
        self.root = root ?? AppPaths.stateSubdirectory(AppPaths.traceDirectoryName)
    }

    /// `FileManager` 는 Sendable 이 아니라 저장하지 않는다 — 조회·생성뿐이라 기본 인스턴스로 충분하다.
    private var fm: FileManager { .default }

    private func file(for sessionID: String) -> URL {
        root.appendingPathComponent("\(sessionID).jsonl")
    }

    public func record(_ event: TraceEvent, sessionID: String) throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(event)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        let url = file(for: sessionID)
        if fm.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func load(sessionID: String) -> [TraceEvent] {
        let url = file(for: sessionID)
        // 파일이 없으면 아직 기록이 없는 세션 — 에러가 아니라 빈 목록이다.
        guard fm.fileExists(atPath: url.path) else { return [] }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            CoreDiagnostics.warn("TraceStore: cannot read \(url.lastPathComponent): \(error.localizedDescription)")
            return []
        }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line -> TraceEvent? in
            guard let d = line.data(using: .utf8) else { return nil }
            do {
                return try decoder.decode(TraceEvent.self, from: d)
            } catch {
                return nil
            }
        }
    }

    public func loadAll() -> [TraceEvent] {
        sessionIDs().flatMap { load(sessionID: $0) }.sorted { $0.t < $1.t }
    }

    public func sessionIDs() -> [String] {
        // 디렉터리가 아직 없으면 트레이스를 한 번도 안 쌓은 것 — 에러가 아니라 빈 목록이다.
        guard fm.fileExists(atPath: root.path) else { return [] }
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            CoreDiagnostics.warn("TraceStore: cannot list \(root.path): \(error.localizedDescription)")
            return []
        }
        return items.filter { $0.pathExtension == "jsonl" }.map { $0.deletingPathExtension().lastPathComponent }
    }

    public func events(forRoom roomID: String) -> [TraceEvent] {
        loadAll().filter { $0.roomID == nil || $0.roomID == roomID }
    }
}

/// 스냅샷 시점의 방·스킬 실측을 TraceEvent 로 만든다. 저장소 jsonl 과 합친다.
enum TraceCollector {
    static func events(
        placements: [PlacementDTO],
        skillNames: [String],
        usage: [String: SkillUsage],
        toolbelts: [String: [String]],
        usageKnown: Bool,
        store: TraceStore
    ) -> [TraceEvent] {
        var out: [TraceEvent] = store.loadAll()
        let referenced = Set(toolbelts.values.flatMap { $0 })
        for placement in placements {
            let born = (placement.createdAt ?? placement.updatedAt ?? 0) / 1000
            guard born > 0 else { continue }
            let state: NodeState
            switch placement.state {
            case "completed": state = .done
            case "rejected": state = .block
            case "executing", "active": state = .exec
            default: state = .queue
            }
            out.append(TraceEvent(
                t: born,
                lane: 3,
                label: placement.title ?? placement.id,
                state: state,
                detail: placement.state,
                diamond: true,
                roomID: placement.id
            ))
            for room in placement.rooms ?? [] {
                out.append(TraceEvent(
                    t: born,
                    lane: 2,
                    label: room.blueprintSlug ?? room.id,
                    state: (room.humanGate ?? false) ? .gate : ((room.blockedCount ?? 0) > 0 ? .block : .exec),
                    detail: room.state,
                    roomID: room.id
                ))
            }
        }
        for name in skillNames {
            let hit = usage[name]
            if let last = hit?.lastCalledAt, last > 0, (hit?.callCount ?? 0) > 0 {
                out.append(TraceEvent(
                    t: last,
                    lane: 1,
                    label: name,
                    state: .exec,
                    detail: CLILocalization.format("TraceStore.detail", hit?.callCount ?? 0),
                    roomID: "skill-\(name)"
                ))
            } else if usageKnown, referenced.contains(name) {
                let t = hit?.lastCalledAt ?? 0
                guard t > 0 else { continue }
                out.append(TraceEvent(
                    t: t,
                    lane: 4,
                    label: name,
                    state: .gate,
                    dashed: true,
                    detail: CLILocalization.string("TraceStore.detail-2"),
                    roomID: "skill-\(name)"
                ))
            }
        }
        return out.sorted { $0.t < $1.t }
    }
}
