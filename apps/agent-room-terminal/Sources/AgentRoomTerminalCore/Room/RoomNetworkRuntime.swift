import Foundation
import RoomKit

public struct RoomNetworkBinding: Equatable, Sendable {
    public var wall: NetworkWall
    public var proxyPort: UInt16?

    public init(wall: NetworkWall, proxyPort: UInt16? = nil) {
        self.wall = wall
        self.proxyPort = proxyPort
    }

    public var jsonObject: [String: Any] {
        RoomNetworkJSON.object(wall: wall, proxyPort: proxyPort)
    }
}

public enum RoomNetworkRuntime {
    public static func bind(
        wall: NetworkWall,
        roomURL: URL,
        client: DaemonClient
    ) throws -> RoomNetworkBinding {
        guard case .allow(let domains) = wall else {
            return RoomNetworkBinding(wall: wall, proxyPort: nil)
        }
        let response = try client.send(
            .ensureNetworkProxy(roomDir: roomURL.path, allowedDomains: domains)
        )
        guard response.ok, let port = response.result?["proxyPort"]?.int, port > 0, port <= Int(UInt16.max) else {
            throw DaemonProtocolError.requestFailed(
                response.error ?? "ensureNetworkProxy failed"
            )
        }
        let proxyPort = UInt16(port)
        try RoomEnvFile.applyProxy(roomURL: roomURL, wall: wall, proxyPort: proxyPort)
        return RoomNetworkBinding(wall: wall, proxyPort: proxyPort)
    }
}
