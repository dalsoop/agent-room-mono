import Foundation

struct BindStore: Sendable {
    let url: URL
    let files: RoomFiles

    init(url: URL, files: RoomFiles = RoomFiles()) {
        self.url = url
        self.files = files
    }

    func load() throws -> [RoomWorktreeBind] {
        guard files.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RoomWorktreeBind].self, from: data)
    }

    func save(_ binds: [RoomWorktreeBind]) throws {
        let dir = url.deletingLastPathComponent()
        try files.createDirectory(at: dir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(binds)
        try data.write(to: url, options: .atomic)
    }

    func upsert(_ bind: RoomWorktreeBind) throws -> [RoomWorktreeBind] {
        var all = try load()
        if let idx = all.firstIndex(where: { $0.roomID == bind.roomID }) {
            all[idx] = bind
        } else {
            all.append(bind)
        }
        try save(all)
        return all
    }

    func find(roomID: String) throws -> RoomWorktreeBind {
        let all = try load()
        guard let found = all.first(where: { $0.roomID == roomID }) else {
            throw AgentRoomWorktreeError.bindNotFound(roomID)
        }
        return found
    }
}
