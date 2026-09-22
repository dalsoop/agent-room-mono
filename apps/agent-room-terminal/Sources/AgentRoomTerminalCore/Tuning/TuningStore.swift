import Foundation

/// GUI 설정과 PATH CLI `tuning` 이 공유하는 5개 값. 정본은 AppPaths 상태 JSON.
public struct TuningValues: Codable, Equatable, Sendable {
    public var idleSeconds: Double
    public var ringLines: Int
    public var handoffFactor: Double
    public var replayCount: Int
    public var promoteSuccesses: Int

    public init(
        idleSeconds: Double = 60,
        ringLines: Int = 10_000,
        handoffFactor: Double = 0.8,
        replayCount: Int = 3,
        promoteSuccesses: Int = 5
    ) {
        self.idleSeconds = idleSeconds
        self.ringLines = ringLines
        self.handoffFactor = handoffFactor
        self.replayCount = replayCount
        self.promoteSuccesses = promoteSuccesses
    }

    private enum CodingKeys: String, CodingKey {
        case idleSeconds
        case ringLines
        case handoffFactor
        case replayCount
        case promoteSuccesses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.idleSeconds = try container.decodeIfPresent(Double.self, forKey: .idleSeconds) ?? 60
        self.ringLines = try container.decodeIfPresent(Int.self, forKey: .ringLines) ?? 10_000
        self.handoffFactor = try container.decodeIfPresent(Double.self, forKey: .handoffFactor) ?? 0.8
        self.replayCount = try container.decodeIfPresent(Int.self, forKey: .replayCount) ?? 3
        self.promoteSuccesses = try container.decodeIfPresent(Int.self, forKey: .promoteSuccesses) ?? 5
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(idleSeconds, forKey: .idleSeconds)
        try container.encode(ringLines, forKey: .ringLines)
        try container.encode(handoffFactor, forKey: .handoffFactor)
        try container.encode(replayCount, forKey: .replayCount)
        try container.encode(promoteSuccesses, forKey: .promoteSuccesses)
    }

    public static let `default` = TuningValues()

    public var habit: HabitTuning {
        HabitTuning(recentCount: replayCount, promoteMinSuccess: promoteSuccesses)
    }

    public func jsonObject() -> [String: Any] {
        [
            TuningKey.idleSeconds.rawValue: idleSeconds,
            TuningKey.ringLines.rawValue: ringLines,
            TuningKey.handoffFactor.rawValue: handoffFactor,
            TuningKey.replayCount.rawValue: replayCount,
            TuningKey.promoteSuccesses.rawValue: promoteSuccesses,
        ]
    }
}

public enum TuningKey: String, CaseIterable, Sendable {
    case idleSeconds
    case ringLines
    case handoffFactor
    case replayCount
    case promoteSuccesses
}

public enum TuningError: Error, Equatable, LocalizedError {
    case unknownKey(String)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case .unknownKey(let key):
            return "unknown tuning key: \(key)"
        case .invalidValue(let value):
            return "invalid tuning value: \(value)"
        }
    }
}

public struct TuningStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func `default`(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TuningStore {
        TuningStore(fileURL: AppPaths.stateFile("tuning.json", environment: environment))
    }

    public func load() throws -> TuningValues {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return .default }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(TuningValues.self, from: data)
    }

    public func show() throws -> TuningValues {
        try load()
    }

    @discardableResult
    public func set(key: String, value: String) throws -> TuningValues {
        guard let parsed = TuningKey(rawValue: key) else {
            throw TuningError.unknownKey(key)
        }
        var current = try load()
        try apply(key: parsed, value: value, into: &current)
        try save(current)
        return current
    }

    private func save(_ values: TuningValues) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: fileURL, options: .atomic)
    }

    private func apply(key: TuningKey, value: String, into values: inout TuningValues) throws {
        switch key {
        case .idleSeconds:
            values.idleSeconds = try Self.double(value)
        case .ringLines:
            values.ringLines = try Self.int(value)
        case .handoffFactor:
            values.handoffFactor = try Self.double(value)
        case .replayCount:
            values.replayCount = try Self.int(value)
        case .promoteSuccesses:
            values.promoteSuccesses = try Self.int(value)
        }
    }

    private static func int(_ raw: String) throws -> Int {
        guard let value = Int(raw) else { throw TuningError.invalidValue(raw) }
        return value
    }

    private static func double(_ raw: String) throws -> Double {
        guard let value = Double(raw) else { throw TuningError.invalidValue(raw) }
        return value
    }
}
