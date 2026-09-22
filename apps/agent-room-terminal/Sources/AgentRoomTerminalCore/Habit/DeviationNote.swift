import Foundation

/// `habit note --deviated` — `state/notes/<ts>-deviation-<번호>.md`.
public struct DeviationNote: Equatable, Sendable {
    public var number: Int
    public var reason: String
    public var procedure: String
    public var url: URL

    public init(number: Int, reason: String, procedure: String, url: URL) {
        self.number = number
        self.reason = reason
        self.procedure = procedure
        self.url = url
    }
}

public struct DeviationNoteStore: Sendable {
    public var clock: any DaemonClock

    public init(clock: any DaemonClock = SystemDaemonClock()) {
        self.clock = clock
    }

    public func record(
        room: URL,
        number: Int,
        reason: String,
        procedure: String? = nil
    ) throws -> DeviationNote {
        try FileManager.default.createDirectory(
            at: HabitFile.notes(in: room),
            withIntermediateDirectories: true
        )
        let body = Self.body(number: number, reason: reason, procedure: procedure ?? reason)
        let url = HabitFile.notes(in: room).appendingPathComponent(filename(number: number))
        try Data(body.utf8).write(to: url, options: .atomic)
        return DeviationNote(
            number: number,
            reason: reason,
            procedure: procedure ?? reason,
            url: url
        )
    }

    public func hasNote(room: URL, number: Int) throws -> Bool {
        let found = try notes(in: room, number: number)
        return !found.isEmpty
    }

    public func notes(in room: URL, number: Int) throws -> [URL] {
        let dir = HabitFile.notes(in: room)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        let marker = "-deviation-\(HabitFile.padded(number)).md"
        return names.filter { $0.hasSuffix(marker) }.map { dir.appendingPathComponent($0) }
    }

    public func writeAmendRequest(room: URL, handoffID: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: HabitFile.notes(in: room),
            withIntermediateDirectories: true
        )
        let name = "\(timestamp())-amend-request-\(handoffID).md"
        let url = HabitFile.notes(in: room).appendingPathComponent(name)
        let body = "보강 요구\n빈병: \(handoffID)\n전임 세션이 살아 있으니 빈병을 보강한다.\n"
        try Data(body.utf8).write(to: url, options: .atomic)
        return url
    }

    public func writeEscalation(room: URL, handoffID: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: HabitFile.notes(in: room),
            withIntermediateDirectories: true
        )
        let name = "\(timestamp())-escalated-\(handoffID).md"
        let url = HabitFile.notes(in: room).appendingPathComponent(name)
        let body = "escalated\n빈병: \(handoffID)\nmaxBottleSwaps 초과. 더 시도하지 않는다.\n"
        try Data(body.utf8).write(to: url, options: .atomic)
        return url
    }

    private func filename(number: Int) -> String {
        "\(timestamp())-deviation-\(HabitFile.padded(number)).md"
    }

    private func timestamp() -> String {
        String(Int(clock.now().timeIntervalSince1970))
    }

    static func body(number: Int, reason: String, procedure: String) -> String {
        let text = """
        # 이탈 \(HabitFile.padded(number))
        이유: \(reason)

        ## 새 절차
        \(procedure)

        """
        return text
    }
}
