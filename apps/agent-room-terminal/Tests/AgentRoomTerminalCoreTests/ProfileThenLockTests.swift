import XCTest
import RoomKit
@testable import AgentRoomTerminalCore

final class ProfileThenLockTests: XCTestCase {
    func testFsUsageParsing() {
        let sampleFsUsage = """
        # fs_usage sample log
        15:42:01.123  open           /Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/Package.swift          0.000012   swift
        15:42:01.124  write          /Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/Sources/main.swift      0.000015   swift
        15:42:01.125  connect        api.anthropic.com:443                                                        0.000020   curl
        15:42:01.126  write          /Users/jeonghan/.zshrc                                                       0.000010   sh
        """

        let lines = sampleFsUsage.components(separatedBy: "\n")
        let footprint = TraceLogParser.parseFsUsage(lines: lines, argv: ["swift", "build"], exitCode: 0, durationMs: 250)

        XCTAssertEqual(footprint.exitCode, 0)
        XCTAssertEqual(footprint.durationMs, 250)
        XCTAssertTrue(footprint.fileReads.contains("/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/Package.swift"))
        XCTAssertTrue(footprint.fileWrites.contains("/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/Sources/main.swift"))
        XCTAssertTrue(footprint.fileWrites.contains("/Users/jeonghan/.zshrc"))
        XCTAssertTrue(footprint.networkOutbound.contains("api.anthropic.com:443"))
        XCTAssertTrue(footprint.childProcesses.contains("swift"))
        XCTAssertTrue(footprint.childProcesses.contains("curl"))
    }

    func testOpensnoopParsing() {
        let sampleOpensnoop = """
        UID    PID COMM          FD ERR PATH
        501  12345 swift          3   0 /Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/Package.swift
        501  12346 git            4   0 /Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/.git/config
        """

        let lines = sampleOpensnoop.components(separatedBy: "\n")
        let footprint = TraceLogParser.parseOpensnoop(lines: lines, argv: ["git", "status"], exitCode: 0)

        XCTAssertTrue(footprint.fileReads.contains("/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/Package.swift"))
        XCTAssertTrue(footprint.fileReads.contains("/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/.git/config"))
        XCTAssertTrue(footprint.childProcesses.contains("swift"))
        XCTAssertTrue(footprint.childProcesses.contains("git"))
    }

    func testDraftGenerationAndTenantViolationDiagnosis() {
        let footprint = ExecutionFootprint(
            argv: ["mytool", "run"],
            exitCode: 0,
            durationMs: 120,
            fileReads: ["/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/input.txt"],
            fileWrites: [
                "/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/output.txt",
                "/Users/jeonghan/.zshrc", // 민감 시스템 파일
                "/Users/jeonghan/.config/rogue/data.json", // 테넌트 경계 밖 쓰기
            ],
            networkOutbound: ["gujo.test:443", "api.service.local:8080"],
            childProcesses: ["mytool", "grep", "sed"]
        )

        let tenantBoundary = "/Users/jeonghan/.tenants/gujo"
        let draft = ProfileThenLock.generateDraft(
            footprint: footprint,
            roomURL: URL(fileURLWithPath: "/Users/jeonghan/.tenants/gujo/rooms/plan1/room1"),
            tenantBoundary: tenantBoundary
        )

        // 1. 민감 파일 .zshrc 는 allowWrite에 들어가지 않고 denyWrite에 위치
        XCTAssertFalse(draft.walls.filesystem.allowWrite.contains("/Users/jeonghan/.zshrc"))
        XCTAssertTrue(draft.walls.filesystem.denyWrite.contains("/Users/jeonghan/.zshrc"))

        // 2. 테넌트 경계 밖 쓰기는 allowWrite에서 제외되고 violations로 진단
        XCTAssertFalse(draft.walls.filesystem.allowWrite.contains("/Users/jeonghan/.config/rogue/data.json"))
        let rogueViolation = draft.violations.first { $0.path.contains(".config/rogue") }
        XCTAssertNotNil(rogueViolation)
        XCTAssertEqual(rogueViolation?.operation, "write")

        // 3. 정상 테넌트 내부 쓰기는 allowWrite에 포함
        XCTAssertTrue(draft.walls.filesystem.allowWrite.contains("/Users/jeonghan/.tenants/gujo/rooms/plan1/room1/work/output.txt"))

        // 4. 네트워크 벽에 감지된 도메인이 반영됨
        if case .allow(let domains) = draft.walls.network {
            XCTAssertTrue(domains.contains("gujo.test") || domains.contains("gujo.test:443"))
        } else {
            XCTFail("네트워크 벽이 .allow 여야 함: \(draft.walls.network)")
        }

        // 5. 실행 도구 벽에 감지된 바이너리들이 allowList로 락다운
        if case .allowList(let list) = draft.walls.executables {
            XCTAssertTrue(list.contains("mytool"))
            XCTAssertTrue(list.contains("grep"))
            XCTAssertTrue(list.contains("sed"))
        } else {
            XCTFail("실행 도구 벽이 .allowList 여야 함")
        }

        // 6. 도구 개수(3개) 및 빌드 도구 아님 -> toolbelt 추천
        XCTAssertEqual(draft.suggestedPreset, .toolbelt)

        // 7. 마크다운 리포트 생성 확인
        let report = draft.markdownReport()
        XCTAssertTrue(report.contains("방 벽 초안"))
        XCTAssertTrue(report.contains("output.txt"))
        XCTAssertTrue(report.contains("정책/테넌트 위반 지점"))
    }
}
