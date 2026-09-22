import Foundation
import Testing
@testable import AgentRoomTerminalCore

@Suite("RoomPaths.tenantsRoot — ~/.tenants 는 홈 한 층의 규약")
struct RoomPathsTenantsRootTests {
    @Test("상태 루트가 이미 .tenants/<slug> 안이면 그 .tenants 를 쓴다(겹치지 않는다)")
    func insideTenantRootReusesTenantsDirectory() {
        let root = RoomPaths.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/personal"],
            homeDirectory: "/Users/x"
        )
        #expect(root.path == "/Users/x/.tenants")
    }

    @Test("방 안 세션(상태 루트가 방 폴더)도 같은 .tenants 로 올라간다")
    func insideRoomFolderClimbsToTenantsDirectory() {
        let root = RoomPaths.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/gujo/rooms/L1/seller/state"],
            homeDirectory: "/Users/x"
        )
        #expect(root.path == "/Users/x/.tenants")
    }

    @Test("루트가 밖(테스트 임시 폴더)이면 그 밑에 .tenants 를 둔다")
    func outsideRootNestsTenantsDirectory() {
        let root = RoomPaths.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/tmp/isolated"],
            homeDirectory: "/Users/x"
        )
        #expect(root.path == "/tmp/isolated/.tenants")
    }
}

@Suite("RoomPaths.tenantStateRoot — 방 env 의 상태 루트는 방의 테넌트")
struct RoomPathsTenantStateRootTests {
    @Test("지휘실이 personal 이어도 gujo 방의 루트는 .tenants/gujo")
    func gujoRoomFromPersonalCommandRoom() {
        let root = RoomPaths.tenantStateRoot(
            tenant: "tenant:gujo",
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/personal"],
            homeDirectory: "/Users/x"
        )
        #expect(root.path == "/Users/x/.tenants/gujo")
    }
}
