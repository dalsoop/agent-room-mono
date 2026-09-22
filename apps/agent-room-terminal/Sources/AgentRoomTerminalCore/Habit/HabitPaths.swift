import Foundation

/// 방 폴더 안 습관·노트·빈병 경로. 방 URL 은 호출자가 StateRootKit 조립본을 넘긴다.
enum HabitFile {
    static let habitsDir = "habits"
    static let indexName = "INDEX.md"
    static let stateDir = "state"
    static let notesDir = "notes"
    static let termLogName = "term.log"
    static let handoffDir = "handoff"
    static let roomJSONName = "ROOM.json"
    static let envName = "env"
    static let suffix = ".habit.json"
    static let candidatesName = "candidates.jsonl"
    static let overflowPrefix = "… 외 "
    static let overflowSuffix = "건"
    static let wikiCLI = "agent-wiki"

    static func padded(_ number: Int) -> String {
        String(format: "%04d", number)
    }

    static func habits(in room: URL) -> URL {
        room.appendingPathComponent(habitsDir, isDirectory: true)
    }

    static func index(in room: URL) -> URL {
        habits(in: room).appendingPathComponent(indexName)
    }

    static func candidates(in room: URL) -> URL {
        habits(in: room).appendingPathComponent(candidatesName)
    }

    static func habitURL(in room: URL, number: Int, slug: String) -> URL {
        let name = "\(padded(number))-\(slug)\(suffix)"
        return habits(in: room).appendingPathComponent(name)
    }

    static func state(in room: URL) -> URL {
        room.appendingPathComponent(stateDir, isDirectory: true)
    }

    static func notes(in room: URL) -> URL {
        state(in: room).appendingPathComponent(notesDir, isDirectory: true)
    }

    static func termLog(in room: URL) -> URL {
        state(in: room).appendingPathComponent(termLogName)
    }

    static func handoff(in room: URL, id: String) -> URL {
        room.appendingPathComponent(handoffDir, isDirectory: true)
            .appendingPathComponent("\(id).json")
    }

    static func roomJSON(in room: URL) -> URL {
        room.appendingPathComponent(roomJSONName)
    }

    static func env(in room: URL) -> URL {
        room.appendingPathComponent(envName)
    }

    static func simulateFailures(in room: URL) -> URL {
        state(in: room).appendingPathComponent("simulate-failures.json")
    }

    static func slug(from title: String) -> String {
        let lowered = title.lowercased()
        var chars: [Character] = []
        var pendingHyphen = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen, !chars.isEmpty { chars.append("-") }
                pendingHyphen = false
                chars.append(Character(scalar))
            } else {
                pendingHyphen = true
            }
        }
        let text = String(chars)
        return text.isEmpty ? "habit" : text
    }
}

enum HabitJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct RoomHabitContext: Decodable, Equatable, Sendable {
    var id: String
    var task: String
    var verdict: String

    static func load(room: URL) throws -> RoomHabitContext {
        let url = HabitFile.roomJSON(in: room)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HabitError.roomContextMissing
        }
        let data = try Data(contentsOf: url)
        return try HabitJSON.decoder().decode(RoomHabitContext.self, from: data)
    }
}

struct HabitHandoffSnapshot: Codable, Equatable, Sendable {
    var id: String
    var sessionID: String
    var planID: String
    var roomID: String
    var snapshot: String
    var verdictOutput: String
    var successorOccupant: String
    var successorHandle: String
    var habitCandidates: [HabitCandidate]

    enum CodingKeys: String, CodingKey {
        case id, sessionID, planID, roomID, snapshot, verdictOutput, successorOccupant, successorHandle, habitCandidates
    }

    init(
        id: String,
        sessionID: String,
        planID: String,
        roomID: String,
        snapshot: String,
        verdictOutput: String,
        successorOccupant: String = "",
        successorHandle: String = "",
        habitCandidates: [HabitCandidate] = []
    ) {
        self.id = id
        self.sessionID = sessionID
        self.planID = planID
        self.roomID = roomID
        self.snapshot = snapshot
        self.verdictOutput = verdictOutput
        self.successorOccupant = successorOccupant
        self.successorHandle = successorHandle
        self.habitCandidates = habitCandidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        planID = try container.decodeIfPresent(String.self, forKey: .planID) ?? ""
        roomID = try container.decodeIfPresent(String.self, forKey: .roomID) ?? ""
        snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot) ?? ""
        verdictOutput = try container.decodeIfPresent(String.self, forKey: .verdictOutput) ?? ""
        successorOccupant = try container.decodeIfPresent(String.self, forKey: .successorOccupant) ?? ""
        successorHandle = try container.decodeIfPresent(String.self, forKey: .successorHandle) ?? ""
        habitCandidates = try container.decodeIfPresent(
            [HabitCandidate].self, forKey: .habitCandidates
        ) ?? []
    }

    static func load(room: URL, id: String) throws -> HabitHandoffSnapshot {
        let url = HabitFile.handoff(in: room, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HabitError.handoffMissing(id)
        }
        return try HabitJSON.decoder().decode(HabitHandoffSnapshot.self, from: try Data(contentsOf: url))
    }
}

enum RoomEnvReader {
    static func value(_ key: String, in room: URL) throws -> String? {
        let url = HabitFile.env(in: room)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if String(parts[0]) == key {
                return parts.count > 1 ? String(parts[1]) : ""
            }
        }
        return nil
    }
}
