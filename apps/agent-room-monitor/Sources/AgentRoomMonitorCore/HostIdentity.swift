import Foundation
import RoomKit

/// 이 프로세스의 입주 표기. 호스트 해석은 AgentOccupant 정본에 위임한다(identity-single-source).
public enum HostIdentity {
    public static func occupantLabel(
        forgeActor: String? = ProcessInfo.processInfo.environment["FORGE_ACTOR"],
        user: String = NSUserName(),
        host: String = AgentOccupant.shortHost()
    ) -> String {
        if let forge = forgeActor?.trimmingCharacters(in: .whitespacesAndNewlines), !forge.isEmpty {
            return forge
        }
        let hostShort = host.split(separator: ".").first.map(String.init) ?? host
        let safeUser = user.isEmpty ? "user" : user
        let safeHost = hostShort.isEmpty ? "host" : hostShort
        return "agent:\(safeUser)@\(safeHost)"
    }
}
