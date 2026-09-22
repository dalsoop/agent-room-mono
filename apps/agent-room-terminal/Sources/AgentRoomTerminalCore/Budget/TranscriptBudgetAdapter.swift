import Foundation
import SQLite3

/// 전사본 기반 판정된 세션 상태.
public enum TranscriptSessionState: String, Codable, Sendable, Equatable {
    case running
    case waiting
    case blocked
    case unknown
}

/// 전사본 예산 및 상태 종합 리포트.
public struct TranscriptBudgetReport: Sendable, Equatable {
    public var used: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int
    public var cacheRead: Int
    public var estimated: Bool
    public var state: TranscriptSessionState
    public var blockedReason: String?
    public var tool: String?
    public var lastActivity: Date?
    public var totals: UsageTotals

    public init(
        used: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        requests: Int = 0,
        cacheRead: Int = 0,
        estimated: Bool = false,
        state: TranscriptSessionState = .unknown,
        blockedReason: String? = nil,
        tool: String? = nil,
        lastActivity: Date? = nil,
        totals: UsageTotals = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
    ) {
        self.used = used
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
        self.cacheRead = cacheRead
        self.estimated = estimated
        self.state = state
        self.blockedReason = blockedReason
        self.tool = tool
        self.lastActivity = lastActivity
        self.totals = totals
    }

    public var isUnknown: Bool {
        state == .unknown && used == 0
    }
}

/// 방 `state/`의 도구별 세션 로그(JSONL, SQLite 등)를 tail/parse하여
/// used 토큰 및 세션 상태(blocked/waiting/running)를 증분 산출하는 어댑터.
public struct TranscriptBudgetAdapter: Sendable {
    public let roomURL: URL
    private let discovery: TranscriptDiscoveryAdapter
    private let parser: TranscriptSessionParserAdapter

    public init(roomURL: URL) {
        self.roomURL = roomURL
        self.discovery = TranscriptDiscoveryAdapter(roomURL: roomURL)
        self.parser = TranscriptSessionParserAdapter()
    }

    public static func inRoom(_ roomURL: URL) -> TranscriptBudgetAdapter {
        TranscriptBudgetAdapter(roomURL: roomURL)
    }

    public func totals() throws -> UsageTotals {
        try report().totals
    }

    public func report() throws -> TranscriptBudgetReport {
        let bindings = try discovery.discoverBindings()
        if bindings.isEmpty {
            return TranscriptBudgetReport()
        }

        let cursorURL = TranscriptCursorAdapter.cursorURL(in: roomURL)
        var cursorStore = TranscriptCursorAdapter.load(from: cursorURL)

        var sum = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        var latestState: TranscriptSessionState = .unknown
        var latestReason: String?
        var primaryTool: String?
        var latestActivity: Date?

        for binding in bindings {
            if binding.tool == AgentRoomTool.agy.rawValue {
                let agyResult = processAgy(binding: binding)
                if agyResult.totals.inputTokens > 0 || agyResult.totals.outputTokens > 0 {
                    sum = sum.adding(agyResult.totals)
                }
                if let st = agyResult.state, st != .unknown {
                    latestState = st
                    latestReason = agyResult.blockedReason
                }
                primaryTool = binding.tool
            } else {
                let fileURLs = TranscriptDiscoveryAdapter.resolveFiles(for: binding)
                for fileURL in fileURLs {
                    let fileResult = processJsonl(fileURL: fileURL, binding: binding, store: &cursorStore)
                    sum = sum.adding(fileResult.totals)
                    if let st = fileResult.state, st != .unknown {
                        latestState = st
                        latestReason = fileResult.blockedReason
                    }
                    if let act = fileResult.activity {
                        latestActivity = act
                    }
                    primaryTool = binding.tool
                }
            }
        }

        try cursorStore.save(to: cursorURL)

        return TranscriptBudgetReport(
            used: sum.inputTokens + sum.outputTokens,
            inputTokens: sum.inputTokens,
            outputTokens: sum.outputTokens,
            requests: sum.requests,
            cacheRead: sum.cacheRead,
            estimated: sum.estimated,
            state: latestState,
            blockedReason: latestReason,
            tool: primaryTool,
            lastActivity: latestActivity,
            totals: sum
        )
    }

    private struct SingleFileResult {
        var totals: UsageTotals
        var state: TranscriptSessionState?
        var blockedReason: String?
        var activity: Date?
    }

    private func processJsonl(
        fileURL: URL,
        binding: TranscriptBinding,
        store: inout TranscriptCursorAdapter
    ) -> SingleFileResult {
        let key = fileURL.path
        let currentSize = fileSize(fileURL)
        var entry = store.files[key] ?? TranscriptCursorEntry()
        if entry.offset > currentSize {
            entry = TranscriptCursorEntry()
        }

        let chunk = readCompleteLines(from: fileURL, offset: entry.offset)
        let tool = AgentRoomTool(rawValue: binding.tool)

        var delta = UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
        var lastState: TranscriptSessionState?
        var lastReason: String?
        var lastDate: Date?

        for line in chunk.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parsed = parser.parseLine(trimmed, tool: tool)
            delta = delta.adding(parsed.totals)
            if let st = parsed.state {
                lastState = st
                lastReason = parsed.blockedReason
            }
            if let dt = parsed.timestamp {
                lastDate = dt
            }
        }

        entry.offset = chunk.newOffset
        entry.inputTokens += delta.inputTokens
        entry.outputTokens += delta.outputTokens
        entry.requests += delta.requests
        entry.cacheRead += delta.cacheRead
        if let st = lastState {
            entry.state = st.rawValue
            entry.blockedReason = lastReason
        }
        entry.tool = binding.tool
        store.files[key] = entry

        let effectiveState = lastState ?? entry.state.flatMap { TranscriptSessionState(rawValue: $0) }
        let effectiveReason = lastReason ?? entry.blockedReason

        return SingleFileResult(
            totals: UsageTotals(
                inputTokens: entry.inputTokens,
                outputTokens: entry.outputTokens,
                requests: entry.requests,
                cacheRead: entry.cacheRead
            ),
            state: effectiveState,
            blockedReason: effectiveReason,
            activity: lastDate
        )
    }

    private func processAgy(binding: TranscriptBinding) -> SingleFileResult {
        let fileURL = URL(fileURLWithPath: binding.path)
        let adapter = AgyUsageAdapter(workdir: roomURL.path)
        let reading = adapter.measure(file: fileURL)

        var state: TranscriptSessionState = .unknown
        var reason: String?
        let dbState = queryAgyDBState(dbPath: binding.path)
        if dbState.state != .unknown {
            state = dbState.state
            reason = dbState.reason
        }

        let totals = reading.unknown
            ? UsageTotals(inputTokens: 0, outputTokens: 0, requests: 0)
            : UsageTotals(
                inputTokens: reading.inputTokens,
                outputTokens: reading.outputTokens,
                requests: reading.requests,
                estimated: reading.estimated
            )
        return SingleFileResult(totals: totals, state: state, blockedReason: reason, activity: nil)
    }

    private func queryAgyDBState(dbPath: String) -> (state: TranscriptSessionState, reason: String?) {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return (.unknown, nil)
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = db else {
            return (.unknown, nil)
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT status, error_message FROM tasks ORDER BY updated_at DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return (.unknown, nil)
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let status = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let errMsg = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            switch status.lowercased() {
            case "failed", "blocked", "error":
                let reason = (errMsg?.isEmpty == false) ? errMsg : "agy task status \(status)"
                return (.blocked, reason)
            case "running", "in_progress":
                return (.running, nil)
            case "waiting", "paused", "waiting_for_input":
                return (.waiting, nil)
            default:
                break
            }
        }
        return (.unknown, nil)
    }

    private func fileSize(_ url: URL) -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            return 0
        }
    }

    private struct LineChunk {
        var lines: [String]
        var newOffset: Int64
    }

    private func readCompleteLines(from fileURL: URL, offset: Int64) -> LineChunk {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return LineChunk(lines: [], newOffset: offset)
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(max(0, offset)))
            let data = handle.readDataToEndOfFile()
            guard !data.isEmpty else {
                return LineChunk(lines: [], newOffset: offset)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return LineChunk(lines: [], newOffset: offset)
            }

            var rawLines = text.components(separatedBy: "\n")
            let hasTrailingNewline = text.hasSuffix("\n")
            if !hasTrailingNewline && !rawLines.isEmpty {
                _ = rawLines.removeLast()
            }
            let validText = hasTrailingNewline ? text : rawLines.joined(separator: "\n").appending("\n")
            let consumedBytes = Int64((validText.data(using: .utf8) ?? Data()).count)
            return LineChunk(lines: rawLines, newOffset: offset + consumedBytes)
        } catch {
            return LineChunk(lines: [], newOffset: offset)
        }
    }
}
