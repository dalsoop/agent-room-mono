import Foundation

enum SimulateAttempts {
    static func count(room: URL, handoffID: String) throws -> Int {
        let table = try load(room: room)
        return table[handoffID] ?? 0
    }

    static func increment(room: URL, handoffID: String) throws -> Int {
        var table = try load(room: room)
        let next = (table[handoffID] ?? 0) + 1
        table[handoffID] = next
        try save(table, room: room)
        return next
    }

    private static func load(room: URL) throws -> [String: Int] {
        let url = HabitFile.simulateFailures(in: room)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return try HabitJSON.decoder().decode([String: Int].self, from: data)
    }

    private static func save(_ table: [String: Int], room: URL) throws {
        try FileManager.default.createDirectory(
            at: HabitFile.state(in: room),
            withIntermediateDirectories: true
        )
        let data = try HabitJSON.encoder().encode(table)
        try data.write(to: HabitFile.simulateFailures(in: room), options: .atomic)
    }
}
