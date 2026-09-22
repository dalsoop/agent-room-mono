import Foundation
import RoomKit

public struct HandoffLink: Equatable, Sendable {
    public var id: String
    public var roomID: String
    public var predecessor: String?

    public init(id: String, roomID: String, predecessor: String?) {
        self.id = id
        self.roomID = roomID
        self.predecessor = predecessor
    }
}

public struct HandoffAmendment: Codable, Equatable, Sendable {
    public var ts: String
    public var note: String
    public var habitNotes: [String]
    public var terminalSnapshot: [String]

    public init(
        ts: String,
        note: String,
        habitNotes: [String],
        terminalSnapshot: [String]
    ) {
        self.ts = ts
        self.note = note
        self.habitNotes = habitNotes
        self.terminalSnapshot = terminalSnapshot
    }
}

struct HandoffDigestNotes: Equatable, Sendable {
    var pitfalls: [String]
    var decisions: [String]
    var remaining: [String]
}

struct HandoffSuccessorTarget: Equatable, Sendable {
    var occupant: String
    var handle: String
}

public struct HandoffBottle: Codable, Equatable, Sendable {
    public var id: String
    public var roomID: String
    public var predecessor: String?
    public var tool: String
    public var note: String
    public var remainingWork: String
    public var rationale: String
    public var habitNotes: [String]
    public var terminalSnapshot: [String]
    public var budget: BudgetState
    public var createdAt: String
    public var amendments: [HandoffAmendment]
    var digestNotes: HandoffDigestNotes
    /// `HabitHandoffSnapshot` 이 같은 파일을 읽도록 싣는다.
    public var sessionID: String
    public var planID: String
    public var snapshot: String
    public var verdictOutput: String
    var successorTarget: HandoffSuccessorTarget
    public var habitCandidates: [HabitCandidate]
    var evidence: HandoffSessionEvidence

    public var successorOccupant: String {
        get { successorTarget.occupant }
        set { successorTarget.occupant = newValue }
    }
    public var successorHandle: String {
        get { successorTarget.handle }
        set { successorTarget.handle = newValue }
    }

    public var pitfalls: [String] {
        get { digestNotes.pitfalls }
        set { digestNotes.pitfalls = newValue }
    }
    public var decisions: [String] {
        get { digestNotes.decisions }
        set { digestNotes.decisions = newValue }
    }
    public var remaining: [String] {
        get { digestNotes.remaining }
        set { digestNotes.remaining = newValue }
    }
    /// 전임이 Read 한 경로. 본문은 싣지 않는다. 옛 JSON 은 빈 배열.
    public var readDocuments: [String] {
        get { evidence.readDocuments }
        set { evidence.readDocuments = newValue }
    }
    /// Bash command 첫 줄. 비밀 인자는 `***`. 옛 JSON 은 빈 배열.
    public var executedCommands: [String] {
        get { evidence.executedCommands }
        set { evidence.executedCommands = newValue }
    }
    /// 방 `work/` 아래 세션 시작 이후 mtime 파일. 옛 JSON 은 빈 배열.
    public var producedFiles: [String] {
        get { evidence.producedFiles }
        set { evidence.producedFiles = newValue }
    }
    /// 마지막 assistant 텍스트 400자. 옛 JSON 은 빈 문자열.
    public var lastAssistantText: String {
        get { evidence.lastAssistantText }
        set { evidence.lastAssistantText = newValue }
    }
    /// `transcript` 또는 전사 없음 `none`. 추정으로 채우지 않는다.
    public var evidenceSource: String {
        get { evidence.evidenceSource }
        set { evidence.evidenceSource = newValue }
    }

    public init(
        id: String,
        roomID: String,
        predecessor: String?,
        tool: String,
        note: String,
        budget: BudgetState,
        createdAt: String,
        remainingWork: String = ""
    ) {
        self.id = id
        self.roomID = roomID
        self.predecessor = predecessor
        self.tool = tool
        self.note = note
        self.remainingWork = remainingWork
        self.rationale = note
        self.habitNotes = []
        self.terminalSnapshot = []
        self.budget = budget
        self.createdAt = createdAt
        self.amendments = []
        self.digestNotes = HandoffDigestNotes(
            pitfalls: [],
            decisions: [],
            remaining: []
        )
        self.sessionID = ""
        self.planID = ""
        self.snapshot = ""
        self.verdictOutput = ""
        self.successorTarget = HandoffSuccessorTarget(occupant: "", handle: "")
        self.habitCandidates = []
        self.evidence = .none
    }

    enum CodingKeys: String, CodingKey {
        case id, roomID, predecessor, tool, note, remainingWork, rationale
        case habitNotes, terminalSnapshot, budget, createdAt, amendments
        case pitfalls, decisions, remaining
        case sessionID, planID, snapshot, verdictOutput, successorOccupant, successorHandle, habitCandidates
        case readDocuments, executedCommands, producedFiles
        case lastAssistantText, evidenceSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        roomID = try container.decode(String.self, forKey: .roomID)
        predecessor = try container.decodeIfPresent(String.self, forKey: .predecessor)
        tool = try container.decode(String.self, forKey: .tool)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        remainingWork = try container.decodeIfPresent(String.self, forKey: .remainingWork) ?? ""
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        habitNotes = try container.decodeIfPresent([String].self, forKey: .habitNotes) ?? []
        terminalSnapshot = try container.decodeIfPresent([String].self, forKey: .terminalSnapshot) ?? []
        budget = try container.decode(BudgetState.self, forKey: .budget)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        amendments = try container.decodeIfPresent([HandoffAmendment].self, forKey: .amendments) ?? []
        digestNotes = HandoffDigestNotes(
            pitfalls: try container.decodeIfPresent([String].self, forKey: .pitfalls) ?? [],
            decisions: try container.decodeIfPresent([String].self, forKey: .decisions) ?? [],
            remaining: try container.decodeIfPresent([String].self, forKey: .remaining) ?? []
        )
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        planID = try container.decodeIfPresent(String.self, forKey: .planID) ?? ""
        snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot)
            ?? terminalSnapshot.joined(separator: "\n")
        verdictOutput = try container.decodeIfPresent(String.self, forKey: .verdictOutput) ?? ""
        successorTarget = HandoffSuccessorTarget(
            occupant: try container.decodeIfPresent(String.self, forKey: .successorOccupant) ?? "",
            handle: try container.decodeIfPresent(String.self, forKey: .successorHandle) ?? ""
        )
        habitCandidates = try container.decodeIfPresent(
            [HabitCandidate].self, forKey: .habitCandidates
        ) ?? []
        evidence = HandoffSessionEvidence(
            readDocuments: try container.decodeIfPresent(
                [String].self, forKey: .readDocuments
            ) ?? [],
            executedCommands: try container.decodeIfPresent(
                [String].self, forKey: .executedCommands
            ) ?? [],
            producedFiles: try container.decodeIfPresent(
                [String].self, forKey: .producedFiles
            ) ?? [],
            lastAssistantText: try container.decodeIfPresent(
                String.self, forKey: .lastAssistantText
            ) ?? "",
            evidenceSource: try container.decodeIfPresent(
                String.self, forKey: .evidenceSource
            ) ?? HandoffSessionEvidence.noneSource
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roomID, forKey: .roomID)
        try container.encodeIfPresent(predecessor, forKey: .predecessor)
        try container.encode(tool, forKey: .tool)
        try container.encode(note, forKey: .note)
        try container.encode(remainingWork, forKey: .remainingWork)
        try container.encode(rationale, forKey: .rationale)
        try container.encode(habitNotes, forKey: .habitNotes)
        try container.encode(terminalSnapshot, forKey: .terminalSnapshot)
        try container.encode(budget, forKey: .budget)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(amendments, forKey: .amendments)
        try container.encode(pitfalls, forKey: .pitfalls)
        try container.encode(decisions, forKey: .decisions)
        try container.encode(remaining, forKey: .remaining)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(planID, forKey: .planID)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encode(verdictOutput, forKey: .verdictOutput)
        try container.encode(successorOccupant, forKey: .successorOccupant)
        try container.encode(successorHandle, forKey: .successorHandle)
        try container.encode(habitCandidates, forKey: .habitCandidates)
        try container.encode(readDocuments, forKey: .readDocuments)
        try container.encode(executedCommands, forKey: .executedCommands)
        try container.encode(producedFiles, forKey: .producedFiles)
        try container.encode(lastAssistantText, forKey: .lastAssistantText)
        try container.encode(evidenceSource, forKey: .evidenceSource)
    }

    public var digest: HandoffDigest {
        HandoffDigest(
            id: id,
            predecessor: predecessor,
            budget: budget,
            tool: tool,
            pitfalls: pitfalls,
            decisions: decisions,
            remaining: remaining
        )
    }
}

public struct HandoffRequest: Sendable {
    public var roomID: String
    public var roomURL: URL
    public var planID: String
    public var note: String
    public var predecessor: String?
    public var parentRoomURL: URL?
    public var tool: AgentRoomTool
    public var budget: BudgetState
    public var occupant: String
    public var successorOccupant: String
    public var successorHandle: String
    public var sessionID: String
    public var wallMode: String
    public var authority: LedgerAuthority
    public var snapshotLines: Int

    public init(
        roomID: String,
        roomURL: URL,
        planID: String,
        note: String,
        predecessor: String?,
        parentRoomURL: URL?,
        tool: AgentRoomTool,
        budget: BudgetState,
        occupant: String,
        successorOccupant: String,
        successorHandle: String,
        sessionID: String,
        wallMode: String,
        authority: LedgerAuthority,
        snapshotLines: Int = 100
    ) {
        self.roomID = roomID
        self.roomURL = roomURL
        self.planID = planID
        self.note = note
        self.predecessor = predecessor
        self.parentRoomURL = parentRoomURL
        self.tool = tool
        self.budget = budget
        self.occupant = occupant
        self.successorOccupant = successorOccupant
        self.successorHandle = successorHandle
        self.sessionID = sessionID
        self.wallMode = wallMode
        self.authority = authority
        self.snapshotLines = snapshotLines
    }
}

enum HandoffJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum HandoffFolder {
    static func directory(in roomURL: URL) -> URL {
        roomURL.appendingPathComponent("handoff", isDirectory: true)
    }

    static func file(in roomURL: URL, id: String) -> URL {
        directory(in: roomURL).appendingPathComponent("\(id).json", isDirectory: false)
    }

    static func notesDirectory(in roomURL: URL) -> URL {
        roomURL
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
    }
}
