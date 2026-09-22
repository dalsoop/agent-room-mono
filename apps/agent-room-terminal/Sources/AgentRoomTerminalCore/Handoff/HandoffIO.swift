import Foundation

enum HandoffIO {
    static func write(_ bottle: HandoffBottle, in roomURL: URL) throws {
        let folder = HandoffFolder.directory(in: roomURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try HandoffJSON.encoder().encode(bottle)
        try data.write(to: HandoffFolder.file(in: roomURL, id: bottle.id), options: .atomic)
    }

    static func read(id: String, in roomURL: URL) throws -> HandoffBottle {
        let url = HandoffFolder.file(in: roomURL, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HandoffError.bottleMissing(id)
        }
        let data = try Data(contentsOf: url)
        do {
            return try HandoffJSON.decoder().decode(HandoffBottle.self, from: data)
        } catch {
            throw HandoffError.jsonInvalid
        }
    }

    static func lastBottle(in roomURL: URL) throws -> HandoffBottle? {
        let bottles = try loadBottles(in: roomURL)
        return bottles.max { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    static func loadBottles(in roomURL: URL) throws -> [HandoffBottle] {
        let folder = HandoffFolder.directory(in: roomURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return [] }
        let names = try fm.contentsOfDirectory(atPath: folder.path)
        var bottles: [HandoffBottle] = []
        for name in names where name.hasSuffix(".json") {
            let id = String(name.dropLast(5))
            bottles.append(try read(id: id, in: roomURL))
        }
        return bottles
    }

    static func habitNotes(in roomURL: URL) throws -> [String] {
        let folder = HandoffFolder.notesDirectory(in: roomURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return [] }
        let names = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        var notes: [String] = []
        for name in names {
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                continue
            }
            notes.append(try String(contentsOf: url, encoding: .utf8))
        }
        return notes
    }

    static func roomID(at roomURL: URL, fallback: String) throws -> String {
        let url = roomURL.appendingPathComponent("ROOM.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        let data = try Data(contentsOf: url)
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = object["id"] as? String,
           !id.isEmpty {
            return id
        }
        return fallback
    }

    static func resolvePredecessor(
        requested: String?,
        roomURL: URL,
        parentRoomURL: URL?
    ) throws -> String? {
        if let requested { return requested }
        if let last = try lastBottle(in: roomURL) { return last.id }
        if let parent = parentRoomURL, let last = try lastBottle(in: parent) {
            return last.id
        }
        return nil
    }

    /// 시뮬레이션 승격 실패 때 빈병 note·pitfalls 에 사유를 보탠다. 옛 스냅샷 JSON 도 허용.
    static func appendDigestNote(
        id: String,
        in roomURL: URL,
        note: String,
        pitfall: String
    ) throws {
        let url = HandoffFolder.file(in: roomURL, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let existing = object["note"] as? String ?? ""
        object["note"] = existing.isEmpty ? note : existing + "\n" + note
        var pitfalls = object["pitfalls"] as? [String] ?? []
        pitfalls.append(pitfall)
        object["pitfalls"] = pitfalls
        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: url, options: .atomic)
    }
}
