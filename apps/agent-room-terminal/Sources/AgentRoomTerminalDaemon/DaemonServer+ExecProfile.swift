import Foundation
import AgentRoomTerminalCore
import RoomKit

extension DaemonServer {
    func execProfile(sessionID: String?, tool: String? = nil, roomDir: String? = nil) -> String? {
        if let sessionID, let session = sessionTable().get(sessionID) {
            if session.sandboxConfig.srtSettingsPath != nil { return nil }
            if let profile = session.sandboxConfig.seatbeltProfile, !profile.isEmpty {
                return profile
            }
        }
        guard let roomDir else { return nil }
        let specURL = URL(fileURLWithPath: roomDir).appendingPathComponent(RoomPaths.specFileName)
        if FileManager.default.fileExists(atPath: specURL.path) {
            do {
                let data = try Data(contentsOf: specURL)
                let spec = try JSONDecoder().decode(RoomSpec.self, from: data)
                guard spec.sandboxBackend != .srt else { return nil }
                let agentTools = tool.map { [$0] } ?? []
                let result = SeatbeltCompiler.compile(
                    spec: spec,
                    roomDir: roomDir,
                    home: NSHomeDirectory(),
                    agentTools: agentTools
                )
                return result.profile
            } catch {
                DaemonLog.append("exec-profile-compile: \(error.localizedDescription)", to: logURL)
                return nil
            }
        }
        // spec.json 이 없는 미조립 방/테스트 방의 경우 기본 RoomWalls 격리 프로필을 컴파일하여 제공
        let fallbackSpec = RoomSpec(
            tenant: "default",
            task: "exec",
            verdict: "true",
            workdir: roomDir,
            walls: RoomWalls()
        )
        let agentTools = tool.map { [$0] } ?? []
        let result = SeatbeltCompiler.compile(
            spec: fallbackSpec,
            roomDir: roomDir,
            home: NSHomeDirectory(),
            agentTools: agentTools
        )
        return result.profile
    }

    func applyTuning(key: String?, value: String?) {
        guard let key, let value else { return }
        if key == "idleSeconds", let parsed = TimeInterval(value) {
            tuning.idleSeconds = parsed
        }
        if key == "ringLines", let parsed = Int(value) {
            tuning.ringLines = parsed
        }
        if key == "ringBytes" || key == "ringByteCapacity" || key == "byteRingCapacity",
           let parsed = Int(value) {
            tuning.ringByteCapacity = parsed
            for session in sessionTable().all() {
                session.updateByteRingCapacity(parsed)
            }
        }
    }
}
