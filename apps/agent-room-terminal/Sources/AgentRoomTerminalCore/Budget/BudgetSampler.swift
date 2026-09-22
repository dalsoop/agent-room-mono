import Foundation
import RoomKit

/// 세션이 살아 있는 동안 주기적으로 사용량을 측정하여
/// `state/usage.jsonl`에 기록하고 `budgetSampled` 이벤트를 `RoomEventLog`에 남긴다.
///
/// 데몬(`DaemonServer+LaunchExec`)이 `exec --launch` 실행 중에 이 수집기를 시작하고,
/// 세션 종료 시 `stopAndFlush()`로 마지막 표본을 남긴다.
public final class BudgetSampler {
    public static let defaultIntervalSeconds: Int = 60

    private let roomURL: URL
    private let tool: AgentRoomTool
    private let intervalSeconds: Int
    private let ledger: UsageLedger
    private let eventLog: RoomEventLog
    private let budgetSpec: ToolBudgetSpec
    private let initialInput: Int
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var stopped = false
    private var lastSampledUsed: Int?

    public init(
        roomURL: URL,
        tool: AgentRoomTool,
        initialInput: Int,
        intervalSeconds: Int = BudgetSampler.defaultIntervalSeconds,
        budgetSpec: ToolBudgetSpec? = nil
    ) {
        self.roomURL = roomURL
        self.tool = tool
        self.initialInput = initialInput
        self.intervalSeconds = max(10, intervalSeconds)
        self.ledger = UsageLedger.inRoom(roomURL)
        self.eventLog = RoomEventLog(roomURL: roomURL)
        self.budgetSpec = budgetSpec ?? ToolBudgetSpec.default(for: tool)
    }

    /// 주기적 수집을 시작한다. 즉시 첫 표본을 남긴다.
    public func start() {
        lock.lock()
        guard timer == nil, !stopped else {
            lock.unlock()
            return
        }
        let source = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "budget-sampler.\(roomURL.lastPathComponent)")
        )
        source.schedule(
            deadline: .now(),
            repeating: .seconds(intervalSeconds)
        )
        source.setEventHandler { [weak self] in
            self?.sample()
        }
        timer = source
        lock.unlock()
        source.resume()
    }

    /// 수집을 중단하고 마지막 표본을 남긴다.
    public func stopAndFlush() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        timer?.cancel()
        timer = nil
        lock.unlock()
        sample()
    }

    private func sample() {
        let totals: UsageTotals
        do {
            totals = try ledger.totals()
        } catch {
            return
        }

        // requests==0 은 측정 소스가 하나도 없다는 뜻(unknown)이므로 기록하지 않는다.
        guard totals.requests > 0 else { return }

        let used = totals.used
        let estimated = totals.estimated

        lock.lock()
        let changed = lastSampledUsed != used
        lastSampledUsed = used
        lock.unlock()

        guard changed || stopped else { return }

        let usable = budgetSpec.usable(initialInput: initialInput)
        let limit = usable > 0 ? usable : nil

        do {
            try eventLog.append(
                RoomEvent.budgetSampled(
                    used: used,
                    limit: limit,
                    estimated: estimated
                )
            )
        } catch {
            logError("budgetSampled event: \(error.localizedDescription)")
        }
    }

    private func logError(_ message: String) {
        let text = "budget-sampler: \(message)\n"
        FileHandle.standardError.write(Data(text.utf8))
    }
}
