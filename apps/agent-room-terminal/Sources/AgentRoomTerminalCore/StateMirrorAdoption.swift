import Foundation
import RoomKit
import StateMirrorKit

/// 상태 미러 게시 지점 — 스캐폴드가 앱 생성 시점에 심는 함대 계약(CLAUDE.md "앱 상태 미러").
///
/// GUI 앱은 핵심 모델 요약을 `~/.swift-app-state/agent-room-terminal.json` 으로 게시해
/// 에이전트·스크립트가 스크린샷 없이 `swift-app-router state agent-room-terminal` 로 읽는다.
public enum StateMirrorAdoption {
    /// StateMirror 파일 키 — `~/.swift-app-state/agent-room-terminal.json`.
    public static let appName = "agent-room-terminal"

    /// 앱 고유 필드 9개 — 픽스처 게시기·테스트가 같은 집합을 본다.
    public static let appFieldKeys = [
        "rooms",
        "liveTerminals",
        "daemonRunning",
        "daemonGeneration",
        "handoffDue",
        "frameP95Ms",
        "parseMsPerChunk",
        "lastDegradeAt",
        "excludedToolsTotal",
    ]

    public struct Fields: Sendable, Equatable {
        public var rooms: Int
        public var liveTerminals: Int
        public var daemonRunning: Bool
        public var daemonGeneration: UInt64
        public var handoffDue: Int
        public var frameP95Ms: Double
        public var parseMsPerChunk: Double
        public var lastDegradeAt: Date?
        public var excludedToolsTotal: Int

        public init(
            rooms: Int = 0,
            liveTerminals: Int = 0,
            daemonRunning: Bool = false,
            daemonGeneration: UInt64 = 0,
            handoffDue: Int = 0,
            frameP95Ms: Double = 0,
            parseMsPerChunk: Double = 0,
            lastDegradeAt: Date? = nil,
            excludedToolsTotal: Int = 0
        ) {
            self.rooms = rooms
            self.liveTerminals = liveTerminals
            self.daemonRunning = daemonRunning
            self.daemonGeneration = daemonGeneration
            self.handoffDue = handoffDue
            self.frameP95Ms = frameP95Ms
            self.parseMsPerChunk = parseMsPerChunk
            self.lastDegradeAt = lastDegradeAt
            self.excludedToolsTotal = excludedToolsTotal
        }

        public static let empty = Fields()
    }

    public struct State: Codable, Sendable {
        public var status: String
        public var lastError: String?
        public var generatedAt: Date
        public var rooms: Int
        public var liveTerminals: Int
        public var daemonRunning: Bool
        public var daemonGeneration: UInt64
        public var handoffDue: Int
        public var frameP95Ms: Double
        public var parseMsPerChunk: Double
        public var lastDegradeAt: String?
        public var excludedToolsTotal: Int

        public init(
            status: String,
            lastError: String? = nil,
            generatedAt: Date = Date(),
            fields: Fields = .empty
        ) {
            self.status = status
            self.lastError = lastError
            self.generatedAt = generatedAt
            self.rooms = fields.rooms
            self.liveTerminals = fields.liveTerminals
            self.daemonRunning = fields.daemonRunning
            self.daemonGeneration = fields.daemonGeneration
            self.handoffDue = fields.handoffDue
            self.frameP95Ms = fields.frameP95Ms
            self.parseMsPerChunk = fields.parseMsPerChunk
            self.lastDegradeAt = fields.lastDegradeAt.map(iso8601)
            self.excludedToolsTotal = fields.excludedToolsTotal
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(lastError, forKey: .lastError)
            try container.encode(generatedAt, forKey: .generatedAt)
            try container.encode(rooms, forKey: .rooms)
            try container.encode(liveTerminals, forKey: .liveTerminals)
            try container.encode(daemonRunning, forKey: .daemonRunning)
            try container.encode(daemonGeneration, forKey: .daemonGeneration)
            try container.encode(handoffDue, forKey: .handoffDue)
            try container.encode(frameP95Ms, forKey: .frameP95Ms)
            try container.encode(parseMsPerChunk, forKey: .parseMsPerChunk)
            try container.encode(lastDegradeAt, forKey: .lastDegradeAt)
            try container.encode(excludedToolsTotal, forKey: .excludedToolsTotal)
        }
    }

    /// 모델 상태가 바뀌는 지점(방 열림/닫힘·LOD·강등·예산 갱신)에서 호출한다.
    public static func publish(_ state: State) {
        StateMirror.publish(app: appName, state)
    }

    public static func publish(
        _ fields: Fields = .empty,
        status: String? = nil,
        lastError: String? = nil
    ) {
        StateMirror.publish(app: appName, State(
            status: status ?? StateMirrorHealth.status(lastError: lastError),
            lastError: lastError,
            fields: fields
        ))
    }

    /// 원장이 비어 픽스처 트리를 그릴 때 쓰는 게시기.
    public static func fixtureFields(
        nodes: [RoomSummary] = RoomListFixture.rooms(),
        liveTerminals: Int = 0,
        frameP95Ms: Double = 0,
        parseMsPerChunk: Double = 0,
        lastDegradeAt: Date? = nil,
        daemonRunning: Bool = false,
        daemonGeneration: UInt64 = 0
    ) -> Fields {
        let rooms = nodes.filter(\.kind.isLedgerRoom)
        return Fields(
            rooms: rooms.count,
            liveTerminals: liveTerminals,
            daemonRunning: daemonRunning,
            daemonGeneration: daemonGeneration,
            handoffDue: handoffDueCount(budgetStates(from: rooms)),
            frameP95Ms: frameP95Ms,
            parseMsPerChunk: parseMsPerChunk,
            lastDegradeAt: lastDegradeAt,
            excludedToolsTotal: excludedToolsTotal(nodes)
        )
    }

    public static func publishFixture(
        nodes: [RoomSummary] = RoomListFixture.rooms(),
        liveTerminals: Int = 0,
        frameP95Ms: Double = 0,
        parseMsPerChunk: Double = 0,
        lastDegradeAt: Date? = nil,
        daemonRunning: Bool = false,
        daemonGeneration: UInt64 = 0,
        lastError: String? = nil
    ) {
        publish(
            fixtureFields(
                nodes: nodes,
                liveTerminals: liveTerminals,
                frameP95Ms: frameP95Ms,
                parseMsPerChunk: parseMsPerChunk,
                lastDegradeAt: lastDegradeAt,
                daemonRunning: daemonRunning,
                daemonGeneration: daemonGeneration
            ),
            lastError: lastError
        )
    }

    /// `Budget.state == handoff-due` 인 방 수. 기존 `Budget` 만 호출한다.
    public static func handoffDueCount(_ states: [BudgetState]) -> Int {
        states.filter { $0.state == .handoffDue }.count
    }

    public static func excludedToolsTotal(_ nodes: [RoomSummary]) -> Int {
        nodes.reduce(0) { $0 + $1.excludedToolCount }
    }

    public static func budgetStates(from rooms: [RoomSummary]) -> [BudgetState] {
        rooms.map { node in
            Budget.compute(
                tool: .claude,
                initialInput: 0,
                used: node.budget.used,
                elapsedMinutes: nil,
                estimatedWorkMinutes: nil
            )
        }
    }

    /// 데몬 `status` — 기존 클라이언트의 `listSessions` 로 판정(클라이언트를 고치지 않는다).
    public static func daemonStatus(client: DaemonClient) -> (running: Bool, generation: UInt64) {
        do {
            let response = try client.send(.listSessions())
            return (response.ok, response.generation)
        } catch {
            let generation = (try? GenerationStore(url: AppPaths.daemonGenerationURL()).readCurrent()) ?? 0
            return (false, generation)
        }
    }

    static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
