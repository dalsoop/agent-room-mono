import Darwin
import Foundation
import StateRootKit

/// `room-graph.json` 좌석 사슬. 생산자 여분 필드는 버린다.
public struct RoomGraphSeatChain: Equatable, Sendable {
    public var roomID: String
    public var predecessor: String
    public var current: String
    public var successor: String
    public var session: String

    public init(
        roomID: String,
        predecessor: String,
        current: String,
        successor: String,
        session: String
    ) {
        self.roomID = roomID
        self.predecessor = predecessor
        self.current = current
        self.successor = successor
        self.session = session
    }
}

/// 읽기 실패는 던진다 — 빈 결과로 덮지 않는다(Zero-Loss).
public enum RoomGraphSeatChainError: Error, Equatable, Sendable {
    case unreadable(String)
    case corrupted(String)
}

/// 한 번 읽은 결과. `stale` 는 파일 mtime 이 `staleAfter` 보다 오래됐다는 뜻이고, 화면은 그것을 그대로 표시한다.
public struct RoomGraphSeatChainFeed: Equatable, Sendable {
    public var chains: [String: RoomGraphSeatChain]
    public var generatedAt: String
    public var modifiedAt: Date?
    public var stale: Bool

    public init(chains: [String: RoomGraphSeatChain], generatedAt: String, modifiedAt: Date?, stale: Bool) {
        self.chains = chains
        self.generatedAt = generatedAt
        self.modifiedAt = modifiedAt
        self.stale = stale
    }
}

public enum RoomGraphSeatChainReader {
    /// 이보다 오래된 스냅샷은 stale 로 표시한다(agent-work-todo 가 방 변화마다 다시 쓴다).
    public static let staleAfter: TimeInterval = 600

    public static func file(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        let tenantID: String?
        switch homeDirectory {
        case .some(let home):
            tenantID = StateRootKit.currentTenantID(homeDirectory: home)
        case .none:
            tenantID = StateRootKit.currentTenantID()
        }
        switch tenantSlug(tenantID) {
        case .none:
            return StateRootKit.url(
                ".swift-app-state/room-graph.json",
                environment: environment,
                homeDirectory: homeDirectory
            )
        case .some(let slug):
            let relative = "\(StateRootKit.tenantsDirectoryName)/\(slug)/.swift-app-state/room-graph.json"
            return URL(fileURLWithPath: StateRootKit.hostPath(
                relative,
                environment: environment,
                homeDirectory: homeDirectory
            ))
        }
    }

    public static func load(
        url: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = staleAfter
    ) throws -> RoomGraphSeatChainFeed {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RoomGraphSeatChainError.unreadable(url.path)
        }
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        var feed: RoomGraphSeatChainFeed
        do {
            feed = try decode(data: data)
        } catch {
            throw RoomGraphSeatChainError.corrupted(url.path)
        }
        feed.modifiedAt = modifiedAt
        feed.stale = isStale(modifiedAt: modifiedAt, now: now, staleAfter: staleAfter)
        return feed
    }

    public static func isStale(modifiedAt: Date?, now: Date, staleAfter: TimeInterval) -> Bool {
        guard let modifiedAt else { return true }
        return now.timeIntervalSince(modifiedAt) > staleAfter
    }

    public static func decode(data: Data) throws -> RoomGraphSeatChainFeed {
        let file = try JSONDecoder().decode(GraphFile.self, from: data)
        var chains: [String: RoomGraphSeatChain] = [:]
        for room in file.rooms {
            guard !room.id.isEmpty else { continue }
            chains[room.id] = RoomGraphSeatChain(
                roomID: room.id,
                predecessor: room.seat.predecessor,
                current: room.seat.identity,
                successor: room.seat.successor,
                session: room.seat.session
            )
        }
        return RoomGraphSeatChainFeed(chains: chains, generatedAt: file.generatedAt, modifiedAt: nil, stale: false)
    }

    private static func tenantSlug(_ tenant: String?) -> String? {
        guard let raw = tenant, !raw.isEmpty else { return nil }
        switch raw.hasPrefix("tenant:") {
        case true:
            return String(raw.dropFirst(7))
        case false:
            return raw
        }
    }

}

/// 부모 디렉터리 vnode write/rename 감시. 폴링하지 않는다.
public final class RoomGraphFileWatcher {
    private let directoryURL: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var source: (any DispatchSourceFileSystemObject)?

    public init(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.directoryURL = fileURL.deletingLastPathComponent()
        self.queue = DispatchQueue(label: "agent-room-terminal.room-graph", qos: .userInitiated)
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        let opened = open(directoryURL.path, O_EVTONLY)
        guard opened >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened,
            eventMask: [.write, .rename],
            queue: queue
        )
        src.setEventHandler { [onChange] in
            onChange()
        }
        src.setCancelHandler {
            close(opened)
        }
        src.resume()
        source = src
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}

private struct GraphFile: Decodable {
    var rooms: [RoomFile]
    var generatedAt: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rooms = try c.decodeIfPresent([RoomFile].self, forKey: .rooms) ?? []
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case rooms, generatedAt
    }
}

private struct RoomFile: Decodable {
    var id: String
    var slug: String
    var seat: SeatFile

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        seat = try c.decodeIfPresent(SeatFile.self, forKey: .seat) ?? SeatFile()
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, seat
    }
}

private struct SeatFile: Decodable {
    var identity: String
    var session: String
    var predecessor: String
    var successor: String

    init(
        identity: String = "",
        session: String = "",
        predecessor: String = "",
        successor: String = ""
    ) {
        self.identity = identity
        self.session = session
        self.predecessor = predecessor
        self.successor = successor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identity = try c.decodeIfPresent(String.self, forKey: .identity) ?? ""
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
        predecessor = try c.decodeIfPresent(String.self, forKey: .predecessor) ?? ""
        successor = try c.decodeIfPresent(String.self, forKey: .successor) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case identity, session, predecessor, successor
    }
}
