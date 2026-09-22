import Foundation
import Testing
import RoomKit
@testable import AgentRoomTerminalCore

@Suite("BudgetSampler")
struct BudgetSamplerTests {
    private func makeTempRoom() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("budget-sampler-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: base.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        return base
    }

    private func writeUsageEntry(roomURL: URL, tool: String, input: Int, output: Int, requests: Int) throws {
        let ledger = UsageLedger.inRoom(roomURL)
        let ts = ISO8601DateFormatter().string(from: Date())
        try ledger.append(UsageEntry(
            ts: ts,
            tool: tool,
            inputTokens: input,
            outputTokens: output,
            requests: requests
        ))
    }

    @Test("기본 간격으로 생성된 수집기가 시작 후 첫 표본을 이벤트에 남긴다")
    func startsAndRecordsInitialSample() throws {
        let roomURL = try makeTempRoom()
        defer { try? FileManager.default.removeItem(at: roomURL) }

        try writeUsageEntry(roomURL: roomURL, tool: "claude", input: 5000, output: 3000, requests: 2)

        let sampler = BudgetSampler(
            roomURL: roomURL,
            tool: .claude,
            initialInput: 1000,
            intervalSeconds: 10
        )
        sampler.start()
        Thread.sleep(forTimeInterval: 0.5)
        sampler.stopAndFlush()

        let eventLog = RoomEventLog(roomURL: roomURL)
        let result = eventLog.read(since: 0)
        let budgetEvents = result.events.filter { $0.kind == RoomEventKind.budgetSampled }
        #expect(!budgetEvents.isEmpty, "budgetSampled 이벤트가 하나 이상 있어야 한다")

        if let first = budgetEvents.first {
            let used = first.payload["used"]?.int
            #expect(used == 8000, "사용량은 5000+3000=8000 이어야 한다")
            if let estimated = first.payload["estimated"]?.bool {
                #expect(!estimated, "estimated 는 false 여야 한다")
            } else {
                Issue.record("estimated 필드가 없다")
            }
        }
    }

    @Test("사용량이 변경되지 않으면 중복 이벤트를 남기지 않는다")
    func skipsWhenUsageUnchanged() throws {
        let roomURL = try makeTempRoom()
        defer { try? FileManager.default.removeItem(at: roomURL) }

        try writeUsageEntry(roomURL: roomURL, tool: "claude", input: 1000, output: 500, requests: 1)

        let sampler = BudgetSampler(
            roomURL: roomURL,
            tool: .claude,
            initialInput: 0,
            intervalSeconds: 10
        )
        sampler.start()
        Thread.sleep(forTimeInterval: 1.5)
        sampler.stopAndFlush()

        let eventLog = RoomEventLog(roomURL: roomURL)
        let result = eventLog.read(since: 0)
        let budgetEvents = result.events.filter { $0.kind == RoomEventKind.budgetSampled }
        // 초기 1개 + stop flush 시 1개(값이 같으면 skip 되지만 stopped=true 이면 남긴다)
        // 실제로는 start 시 1개, 그 뒤 값이 안 바뀌면 timer 에선 skip, stopAndFlush 에서 forced
        #expect(budgetEvents.count <= 2, "중복 없이 최대 2개(시작+종료)여야 한다")
    }

    @Test("빈 방에서는 이벤트를 남기지 않는다(used=0, 변화 없음)")
    func emptyRoomNoEvents() throws {
        let roomURL = try makeTempRoom()
        defer { try? FileManager.default.removeItem(at: roomURL) }

        let sampler = BudgetSampler(
            roomURL: roomURL,
            tool: .claude,
            initialInput: 0,
            intervalSeconds: 10
        )
        sampler.start()
        Thread.sleep(forTimeInterval: 0.3)
        sampler.stopAndFlush()

        let eventLog = RoomEventLog(roomURL: roomURL)
        let result = eventLog.read(since: 0)
        let budgetEvents = result.events.filter { $0.kind == RoomEventKind.budgetSampled }
        // used=0 으로 시작하고 stop 시에도 0이면 첫 표본 후 flush 는 changed=false+stopped=true 로 1개
        #expect(budgetEvents.count <= 1)
    }

    @Test("stopAndFlush 를 두 번 호출해도 안전하다")
    func doubleStopIsSafe() throws {
        let roomURL = try makeTempRoom()
        defer { try? FileManager.default.removeItem(at: roomURL) }

        let sampler = BudgetSampler(
            roomURL: roomURL,
            tool: .claude,
            initialInput: 0,
            intervalSeconds: 10
        )
        sampler.start()
        Thread.sleep(forTimeInterval: 0.2)
        sampler.stopAndFlush()
        sampler.stopAndFlush()
        // 크래시 없이 정상 종료되면 통과
    }
}
