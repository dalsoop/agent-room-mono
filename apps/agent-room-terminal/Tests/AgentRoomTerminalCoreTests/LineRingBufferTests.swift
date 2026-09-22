import XCTest
@testable import AgentRoomTerminalCore

final class LineRingBufferTests: XCTestCase {
    func testOverflowSpillsToFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let spill = dir.appendingPathComponent("state").appendingPathComponent("term.log")
        var ring = LineRingBuffer(capacity: 3, spillURL: spill)
        try ring.appendLine("one")
        try ring.appendLine("two")
        try ring.appendLine("three")
        try ring.appendLine("four")
        XCTAssertEqual(ring.snapshot(last: 10), ["two", "three", "four"])
        let spilled = try String(contentsOf: spill, encoding: .utf8)
        XCTAssertTrue(spilled.contains("one"))
        XCTAssertFalse(spilled.contains("four"))
    }

    func testIngestSplitsOnNewline() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let spill = dir.appendingPathComponent("term.log")
        var ring = LineRingBuffer(capacity: 10, spillURL: spill)
        try ring.ingest("ab")
        try ring.ingest("c\nde\n")
        XCTAssertEqual(ring.snapshot(last: 10), ["abc", "de"])
    }
}
