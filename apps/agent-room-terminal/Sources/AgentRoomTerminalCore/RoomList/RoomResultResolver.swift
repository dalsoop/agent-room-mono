import Foundation
import RoomKit

public struct RoomResultFields: Equatable, Sendable {
    public var resultStatus: String?
    public var resultNotes: String?
    public var resultCommitCount: Int?
    public var ledgerPhase: String?
    public var ledgerExitCode: Int?
    public var lastVerdictExit: Int?
    public var launchLogPath: String?

    public init(
        resultStatus: String? = nil,
        resultNotes: String? = nil,
        resultCommitCount: Int? = nil,
        ledgerPhase: String? = nil,
        ledgerExitCode: Int? = nil,
        lastVerdictExit: Int? = nil,
        launchLogPath: String? = nil
    ) {
        self.resultStatus = resultStatus
        self.resultNotes = resultNotes
        self.resultCommitCount = resultCommitCount
        self.ledgerPhase = ledgerPhase
        self.ledgerExitCode = ledgerExitCode
        self.lastVerdictExit = lastVerdictExit
        self.launchLogPath = launchLogPath
    }

    public var hasResult: Bool { resultStatus != nil }

    public var statusBadge: RoomResultBadge {
        guard let status = resultStatus else { return .none }
        switch status {
        case "done":
            return .done
        case "partial":
            return .partial
        case "blocked":
            return .blocked
        default:
            return .none
        }
    }
}

public enum RoomResultBadge: String, Sendable, Equatable {
    case none
    case done
    case partial
    case blocked
}

public enum RoomResultResolver {
    public static func resolve(
        roomID: String,
        roomDirectoryResolver: (String) -> URL?,
        workdirResolver: (String) -> String?,
        fileReader: (URL) -> Data?
    ) -> RoomResultFields {
        var fields = RoomResultFields()

        let roomDir = roomDirectoryResolver(roomID)
        if let roomDir {
            let logURL = roomDir.appendingPathComponent("launch.log", isDirectory: false)
            if fileReader(logURL) != nil {
                fields.launchLogPath = logURL.path
            }
            fillLedger(roomDir: roomDir, fileReader: fileReader, fields: &fields)
            fillVerdict(roomDir: roomDir, fileReader: fileReader, fields: &fields)
        }

        let workdir = workdirResolver(roomID)
        if let workdir {
            fillResult(workdir: workdir, fileReader: fileReader, fields: &fields)
        }

        return fields
    }

    static func fillLedger(
        roomDir: URL,
        fileReader: (URL) -> Data?,
        fields: inout RoomResultFields
    ) {
        let eventsURL = roomDir.appendingPathComponent("events.jsonl", isDirectory: false)
        guard let data = fileReader(eventsURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        var events: [RoomEvent] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            do {
                let event = try decoder.decode(RoomEvent.self, from: lineData)
                events.append(event)
            } catch {
                continue
            }
        }
        guard !events.isEmpty else { return }
        let status = RoomStatusProjection.reduce(events: events)
        fields.ledgerPhase = status.phase.rawValue
        fields.ledgerExitCode = status.exitCode
    }

    static func fillVerdict(
        roomDir: URL,
        fileReader: (URL) -> Data?,
        fields: inout RoomResultFields
    ) {
        let eventsURL = roomDir.appendingPathComponent("events.jsonl", isDirectory: false)
        guard let data = fileReader(eventsURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        var lastVerdictExit: Int?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            do {
                let event = try decoder.decode(RoomEvent.self, from: lineData)
                if event.kind == RoomEventKind.verdictRan,
                   let exit = event.payload["exit"]?.int {
                    lastVerdictExit = exit
                }
            } catch {
                continue
            }
        }
        fields.lastVerdictExit = lastVerdictExit
    }

    static func fillResult(
        workdir: String,
        fileReader: (URL) -> Data?,
        fields: inout RoomResultFields
    ) {
        let resultURL = URL(fileURLWithPath: workdir)
            .appendingPathComponent(".rf2", isDirectory: true)
            .appendingPathComponent("result.json", isDirectory: false)
        guard let data = fileReader(resultURL) else { return }
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            json = parsed
        } catch {
            return
        }
        fields.resultStatus = json["status"] as? String
        fields.resultNotes = json["notes"] as? String
        if let commits = json["commits"] as? [Any] {
            fields.resultCommitCount = commits.count
        }
    }
}
