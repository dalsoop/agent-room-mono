import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("ExecTimeout — exec --timeout 파싱")
struct ExecTimeoutTests {
    @Test("명시값 파싱")
    func parsesTimeoutValue() throws {
        #expect(try ExecTimeout.parse("90") == 90)
        let encoded = try JSONEncoder().encode(
            DaemonRequest.exec(
                sessionID: "s",
                roomDir: "/tmp/room",
                argv: ["true"],
                timeoutSeconds: 90
            )
        )
        let decoded = try JSONDecoder().decode(DaemonRequest.self, from: encoded)
        #expect(decoded.timeoutSeconds == 90)
    }

    @Test("생략 시 기본 300")
    func defaultsToThreeHundred() throws {
        #expect(try ExecTimeout.parse(nil) == 300)
        let json = Data(#"{"op":"exec","roomDir":"/tmp/room","argv":["true"]}"#.utf8)
        let decoded = try JSONDecoder().decode(DaemonRequest.self, from: json)
        #expect(decoded.timeoutSeconds == nil)
        #expect(ExecTimeout.resolve(decoded.timeoutSeconds) == 300)
    }
}
