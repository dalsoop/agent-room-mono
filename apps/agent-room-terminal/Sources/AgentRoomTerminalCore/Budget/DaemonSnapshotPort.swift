import Foundation

public protocol DaemonSnapshotting: Sendable {
    func snapshot(sessionID: String, lines: Int) throws -> [String]
}

public enum HandoffError: Error, Equatable, LocalizedError {
    case snapshotFailed(String)
    case ledgerFailed(LedgerError)
    case bottleMissing(String)
    case jsonInvalid

    public var errorDescription: String? {
        switch self {
        case .snapshotFailed(let message):
            return "daemon snapshot failed: \(message)"
        case .ledgerFailed(let error):
            return "ledger: \(String(describing: error))"
        case .bottleMissing(let id):
            return "handoff bottle missing: \(id)"
        case .jsonInvalid:
            return "handoff JSON was not readable"
        }
    }
}

/// DaemonClient 를 고치지 않고 snapshot 타입만 쓴다.
public struct DaemonClientSnapshot: DaemonSnapshotting {
    public var client: DaemonClient
    public var defaultLines: Int

    public init(client: DaemonClient, defaultLines: Int = 100) {
        self.client = client
        self.defaultLines = defaultLines
    }

    public func snapshot(sessionID: String, lines: Int) throws -> [String] {
        let response = try client.send(.snapshot(sessionID: sessionID, lines: lines))
        guard response.ok else {
            throw HandoffError.snapshotFailed(response.error ?? "snapshot failed")
        }
        guard let values = response.result?["lines"]?.array else {
            throw HandoffError.snapshotFailed("snapshot result missing lines")
        }
        return values.compactMap(\.string)
    }
}
