import XCTest
@testable import AgentRoomMonitorCore

final class ViewSpecStoreTests: XCTestCase {
    func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        return dir
    }

    func testSeedWhenEmptyWritesFiveSpecs() {
        let dir = makeTempDir()
        let specs = ViewSpecStore(directory: dir).loadOrSeed()
        XCTAssertEqual(specs.map(\.id), ViewSpecStore.seedSpecs.map(\.id))
        XCTAssertEqual(specs.count, ViewSpecStore.seedSpecs.count)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        XCTAssertEqual(files.count, ViewSpecStore.seedSpecs.count)
        XCTAssertTrue(specs.contains(where: { $0.id == "lobby" }))
        XCTAssertTrue(specs.contains(where: { $0.id == "archive" }))
        XCTAssertEqual(specs.first(where: { $0.id == "born-48h" })?.filter?.bornWithinHours, 48)
        XCTAssertEqual(specs.first(where: { $0.id == "problems" })?.filter?.states, ["block", "gate"])
    }

    func testDoesNotReseedExistingDirectory() throws {
        let dir = makeTempDir()
        let custom = ViewSpec(id: "custom", title: ["en": "Custom"], groupBy: "harness", order: 0)
        let data = try JSONEncoder().encode(custom)
        try data.write(to: dir.appendingPathComponent("custom.json"))
        let specs = ViewSpecStore(directory: dir).loadOrSeed()
        XCTAssertEqual(specs.map(\.id), ["custom"])
    }

    func testTolerantDecodeIdOnlyAndSkipsBrokenFiles() throws {
        let dir = makeTempDir()
        try #"{"id":"minimal"}"#.write(to: dir.appendingPathComponent("minimal.json"), atomically: true, encoding: .utf8)
        try "not-json".write(to: dir.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        let specs = ViewSpecStore(directory: dir).loadOrSeed()
        XCTAssertEqual(specs.map(\.id), ["minimal"])
        XCTAssertEqual(specs[0].groupBy, "zone")
        XCTAssertEqual(specs[0].displayTitle(language: "ko"), "minimal")
        XCTAssertEqual(specs[0].displayTitle(language: "en"), "minimal")
    }

    func testDisplayTitlePrefersLanguageThenEnglish() {
        let spec = ViewSpec(id: "x", title: ["ko": "구역 지도", "en": "Zone map"], groupBy: "zone")
        XCTAssertEqual(spec.displayTitle(language: "ko"), "구역 지도")
        XCTAssertEqual(spec.displayTitle(language: "en"), "Zone map")
        XCTAssertEqual(spec.displayTitle(language: "ja"), "Zone map")
    }

    func testBornWithinHoursRoundTrip() throws {
        let spec = ViewSpec(
            id: "born-48h",
            title: ["en": "Born in 48h"],
            groupBy: "zone",
            filter: .init(bornWithinHours: 48)
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ViewSpec.self, from: data)
        XCTAssertEqual(decoded.filter?.bornWithinHours, 48)
        XCTAssertNil(decoded.filter?.kinds)
    }
}
