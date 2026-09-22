import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomGraphSeatChainTests")
struct RoomGraphSeatChainTests {
    @Test("픽스처 JSON 두 방을 방 id 키로 디코드한다")
    func decodeTwoRooms() throws {
        let json = """
        {
          "generatedAt": "2026-09-10T00:00:00Z",
          "rooms": [
            {
              "id": "room-a",
              "slug": "alpha",
              "seat": {
                "identity": "agent:codex@host",
                "session": "sess-1",
                "predecessor": "agent:claude@host",
                "successor": "agent:grok@host"
              }
            },
            {
              "id": "room-b",
              "slug": "beta",
              "seat": {
                "identity": "agent:grok@host",
                "session": "",
                "predecessor": "",
                "successor": ""
              }
            }
          ]
        }
        """
        let chains = try RoomGraphSeatChainReader.decode(data: Data(json.utf8)).chains
        #expect(chains.count == 2)
        #expect(chains["room-a"] == RoomGraphSeatChain(
            roomID: "room-a",
            predecessor: "agent:claude@host",
            current: "agent:codex@host",
            successor: "agent:grok@host",
            session: "sess-1"
        ))
        #expect(chains["room-b"] == RoomGraphSeatChain(
            roomID: "room-b",
            predecessor: "",
            current: "agent:grok@host",
            successor: "",
            session: ""
        ))
    }

    @Test("여분 필드와 누락 필드는 무시하고 빈 문자열로 채운다")
    func ignoresExtraAndMissingFields() throws {
        let json = """
        {
          "generatedAt": "2026-09-10T00:00:00Z",
          "counts": {"rooms": 1},
          "rooms": [
            {
              "id": "room-c",
              "slug": "gamma",
              "attention": "ok",
              "extra": true,
              "seat": {
                "identity": "agent:now@host",
                "unused": 1
              }
            },
            {
              "id": "room-d",
              "slug": "delta"
            }
          ]
        }
        """
        let chains = try RoomGraphSeatChainReader.decode(data: Data(json.utf8)).chains
        #expect(chains["room-c"] == RoomGraphSeatChain(
            roomID: "room-c",
            predecessor: "",
            current: "agent:now@host",
            successor: "",
            session: ""
        ))
        #expect(chains["room-d"] == RoomGraphSeatChain(
            roomID: "room-d",
            predecessor: "",
            current: "",
            successor: "",
            session: ""
        ))
    }

    @Test("잘못된 JSON 은 corrupted 를 던진다 — 빈 결과로 덮지 않는다")
    func invalidJSONThrowsCorrupted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seat-chain-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("room-graph.json")
        try Data("{".utf8).write(to: url)
        #expect(throws: RoomGraphSeatChainError.corrupted(url.path)) {
            try RoomGraphSeatChainReader.load(url: url)
        }
        #expect(throws: RoomGraphSeatChainError.unreadable(dir.appendingPathComponent("none.json").path)) {
            try RoomGraphSeatChainReader.load(url: dir.appendingPathComponent("none.json"))
        }
    }

    @Test("mtime 이 staleAfter 보다 오래되면 stale, 아니면 fresh · generatedAt 을 담는다")
    func stalenessFollowsModificationTime() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seat-chain-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("room-graph.json")
        try Data(#"{"generatedAt":"2026-09-10T01:00:00Z","rooms":[]}"#.utf8).write(to: url)
        let fresh = try RoomGraphSeatChainReader.load(url: url, now: Date(), staleAfter: 600)
        #expect(!fresh.stale)
        #expect(fresh.generatedAt == "2026-09-10T01:00:00Z")
        let later = Date().addingTimeInterval(601)
        let stale = try RoomGraphSeatChainReader.load(url: url, now: later, staleAfter: 600)
        #expect(stale.stale)
        #expect(RoomGraphSeatChainReader.isStale(modifiedAt: nil, now: Date(), staleAfter: 600))
    }

    @Test("file() 은 테넌트 있으면 tenants 아래, 없으면 호스트 상태 루트를 쓴다")
    func filePathFollowsTenantContext() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("seat-chain-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env: [String: String] = [:]

        let hostURL = RoomGraphSeatChainReader.file(environment: env, homeDirectory: home.path)
        #expect(hostURL.path == home.appendingPathComponent(".swift-app-state/room-graph.json").path)

        let contextDir = home.appendingPathComponent(".agent-tenant-isolation-manager", isDirectory: true)
        try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
        try Data(#"{"tenantID":"tenant:personal"}"#.utf8).write(
            to: contextDir.appendingPathComponent("current-context.json")
        )
        let tenantURL = RoomGraphSeatChainReader.file(environment: env, homeDirectory: home.path)
        let expected = home
            .appendingPathComponent(".tenants/personal/.swift-app-state/room-graph.json")
            .path
        #expect(tenantURL.path == expected)
    }
}
