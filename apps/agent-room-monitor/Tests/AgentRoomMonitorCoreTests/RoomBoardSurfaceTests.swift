import XCTest

/// GUI 타깃은 Core 테스트가 링크하지 않으므로 소스로 계약을 고정한다.
final class RoomBoardSurfaceTests: XCTestCase {
    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/AgentRoomMonitor/\(relative)"),
            encoding: .utf8)
    }

    func testMainViewIsSingleFloorGrid() throws {
        let view = try source("MainView.swift")
        XCTAssertTrue(view.contains("FloorGridView(board: board)"))
        XCTAssertFalse(view.contains("RoomBoxView("))
        XCTAssertFalse(view.contains("HexBoardView"))
        XCTAssertFalse(view.contains("rotation3DEffect"))
        XCTAssertFalse(view.contains("breadcrumb"))
        XCTAssertFalse(view.contains("setTilt"))
        XCTAssertFalse(view.contains("demoAdd"))
        let manifest = try String(
            contentsOf: packageRoot().appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("exclude: [\"HexBoard.swift\"]"))
    }

    func testFloorPutsAllRoomsOnOneGrid() throws {
        let floor = try source("FloorGridView.swift")
        XCTAssertTrue(floor.contains("board.floorNodes"))
        XCTAssertTrue(floor.contains("Table("))
        XCTAssertFalse(floor.contains("LazyVGrid"))
        XCTAssertFalse(floor.contains("struct FloorCard"))
        XCTAssertTrue(floor.contains("leaseDetail"))
        XCTAssertTrue(floor.contains("isolationWho"))
        XCTAssertTrue(floor.contains("isolationWrites"))
        XCTAssertTrue(floor.contains("isolationNet"))
        XCTAssertTrue(floor.contains("isolationTenant"))
        XCTAssertTrue(floor.contains("isolationDomain"))
        XCTAssertTrue(floor.contains("writesAreHomeWide"))
        XCTAssertTrue(floor.contains("manyTools"))
        XCTAssertTrue(floor.contains("netText(of: node)"))
        XCTAssertTrue(floor.contains("dropSkill"))
        XCTAssertFalse(floor.contains("enterRoom"))
        let board = try source("BoardModel.swift")
        XCTAssertTrue(board.contains("var floorNodes"))
        XCTAssertTrue(board.contains("case \"room\""))
        XCTAssertTrue(board.contains("sorted"))
        XCTAssertFalse(board.contains("case \"warehouse\""), "창고는 방 그리드에 붙이지 않는다")
        XCTAssertFalse(board.contains("selectedTenantID = snapshot.currentTenantID"))
        XCTAssertFalse(
            board.contains("kindRaw == \"zone\" || node.kindRaw == \"host\" || node.kindRaw == \"warehouse\""))
    }

    func testNewRoomDoorStillWorks() throws {
        let sheet = try source("NewRoomSheet.swift")
        XCTAssertFalse(sheet.contains("test -d ."))
        XCTAssertFalse(sheet.contains("verify = \"true\""))
        XCTAssertFalse(sheet.contains("tenant:personal"))
        XCTAssertTrue(sheet.contains("defaultWorkdir()"))
        XCTAssertTrue(sheet.contains("resolvedTenant"))
        let main = try source("MainView.swift")
        XCTAssertTrue(main.contains("selectTenant"))
        XCTAssertTrue(main.contains("NewRoomSheet"))
        XCTAssertTrue(main.contains("tenantCurrent"))
    }

    func testProductionSourcesForbidHostFixtures() throws {
        let root = packageRoot().appendingPathComponent("Sources")
        let forbidden = [
            "agent:grok@macbook",
            "tenant:personal",
            "TODO(앱 소유자)",
            "내부망 gitlab",
            "Internal gitlab",
            "agent-work-todo spawn-room",
        ]
        var hits: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" || url.pathExtension == "strings" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden where text.contains(token) {
                hits.append("\(url.lastPathComponent): \(token)")
            }
        }
        XCTAssertTrue(hits.isEmpty, "판매 소스에 호스트 고정값이 남아 있다: \(hits.joined(separator: ", "))")
        let floor = try source("FloorGridView.swift")
        XCTAssertTrue(floor.contains("displayName"))
    }

    func testDetailPanelWiresOperateAndAX() throws {
        let panel = try source("DetailPanelView.swift")
        XCTAssertTrue(panel.contains("panelOccupy"))
        XCTAssertTrue(panel.contains("panelDemolish"))
        XCTAssertTrue(panel.contains("handoffPack"))
        XCTAssertTrue(panel.contains("loadAX"))
    }
}
