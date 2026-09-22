import Foundation

public enum RoomKind: String, Sendable, Equatable {
    case commandRoom
    case tenant
    case standingRoom
    case appTile
    case childRoom

    public var hostsTerminal: Bool {
        switch self {
        case .commandRoom, .standingRoom, .childRoom:
            return true
        case .tenant, .appTile:
            return false
        }
    }

    public var isLedgerRoom: Bool {
        switch self {
        case .commandRoom, .standingRoom, .childRoom:
            return true
        case .tenant, .appTile:
            return false
        }
    }
}


public struct RoomOccupant: Sendable, Equatable {
    public var handle: String
    public var isSuccessor: Bool

    public init(handle: String, isSuccessor: Bool) {
        self.handle = handle
        self.isSuccessor = isSuccessor
    }
}

public struct HandoffNote: Sendable, Equatable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct RoomUsage: Sendable, Equatable {
    public var used: Int?
    public var handoffAt: Int
    public var isEstimated: Bool
    public var unknownReason: String?

    public init(used: Int?, handoffAt: Int, isEstimated: Bool = false, unknownReason: String? = nil) {
        self.used = used
        self.handoffAt = handoffAt
        self.isEstimated = isEstimated
        switch used {
        case .none:
            self.unknownReason = unknownReason ?? UnknownBudgetReason.noBinding
        case .some:
            self.unknownReason = nil
        }
    }

    public var isUnknown: Bool { used == nil }

    public var fraction: Double? {
        guard let used, handoffAt > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(handoffAt)))
    }
}

public typealias TenantID = String

public struct RoomSummary: Sendable, Equatable, Identifiable {
    public var id: String
    public var parentID: String?
    public var tenantID: TenantID
    public var kind: RoomKind
    public var title: String
    public var status: RoomStatus
    public var wallPreset: String
    public var wallMode: String
    public var excludedToolCount: Int
    public var budget: RoomUsage
    public var bottles: [HandoffNote]
    public var occupants: [RoomOccupant]
    public var roomMarkdown: String
    public var habitIndex: String
    public var sessionID: String?
    public var isExample: Bool
    public var pid: Int?
    public var path: String?

    public init(
        id: String,
        parentID: String? = nil,
        tenantID: TenantID = "default",
        kind: RoomKind,
        title: String,
        status: RoomStatus
    ) {
        self.id = id
        self.parentID = parentID
        self.tenantID = tenantID
        self.kind = kind
        self.title = title
        self.status = status
        self.wallPreset = "toolbelt"
        self.wallMode = "full"
        self.excludedToolCount = 0
        self.budget = RoomUsage(used: 0, handoffAt: 1)
        self.bottles = []
        self.occupants = []
        self.roomMarkdown = ""
        self.habitIndex = ""
        self.sessionID = nil
        self.isExample = false
        self.pid = nil
        self.path = nil
    }
}
