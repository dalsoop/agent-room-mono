import XCTest
@testable import AgentRoomTerminalCore

final class TuningStoreTests: XCTestCase {
    func testDefaultsAndRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuning-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TuningStore(fileURL: dir.appendingPathComponent("tuning.json"))
        let defaults = try store.show()
        XCTAssertEqual(defaults.idleSeconds, 60)
        XCTAssertEqual(defaults.ringLines, 10_000)
        XCTAssertEqual(defaults.handoffFactor, 0.8)
        XCTAssertEqual(defaults.replayCount, 3)
        XCTAssertEqual(defaults.promoteSuccesses, 5)
        _ = try store.set(key: "idleSeconds", value: "90")
        _ = try store.set(key: "ringLines", value: "200")
        let loaded = try store.show()
        XCTAssertEqual(loaded.idleSeconds, 90)
        XCTAssertEqual(loaded.ringLines, 200)
        XCTAssertEqual(loaded.handoffFactor, 0.8)
    }

    func testLegacyJsonWithObsoleteKeysLoadsSuccessfully() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuning-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("tuning.json")
        let legacyJson = """
        {
          "idleSeconds": 45,
          "ringLines": 5000,
          "handoffFactor": 0.75,
          "replayCount": 4,
          "promoteSuccesses": 6,
          "liveTerminalCap": 12,
          "degradeMs": 30
        }
        """
        try legacyJson.data(using: .utf8)?.write(to: fileURL)

        let store = TuningStore(fileURL: fileURL)
        let loaded = try store.load()
        XCTAssertEqual(loaded.idleSeconds, 45)
        XCTAssertEqual(loaded.ringLines, 5000)
        XCTAssertEqual(loaded.handoffFactor, 0.75)
        XCTAssertEqual(loaded.replayCount, 4)
        XCTAssertEqual(loaded.promoteSuccesses, 6)
    }

    func testRemovedKeysAreNowUnknownKeys() {
        let store = TuningStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("test.json")
        )
        XCTAssertThrowsError(try store.set(key: "liveTerminalCap", value: "10")) { error in
            guard case TuningError.unknownKey(let key) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(key, "liveTerminalCap")
        }
        XCTAssertThrowsError(try store.set(key: "degradeMs", value: "50")) { error in
            guard case TuningError.unknownKey(let key) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(key, "degradeMs")
        }
    }

    func testUnknownKey() {
        let store = TuningStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("nope.json")
        )
        XCTAssertThrowsError(try store.set(key: "nope", value: "1")) { error in
            guard case TuningError.unknownKey = error else {
                return XCTFail("expected unknownKey")
            }
        }
    }
}

