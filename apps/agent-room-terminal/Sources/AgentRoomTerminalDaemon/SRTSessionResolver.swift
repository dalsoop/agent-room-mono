import Foundation
import RoomKit

/// 방의 spec.json 에서 srt 백엔드 여부를 판정하고, srt 설정 JSON 을 렌더링·기록하는 유틸리티.
enum SRTSessionResolver {
    /// spec.json 에서 sandboxBackend 가 .srt 이면 SRT 설정 JSON 을 렌더링하여 방 폴더에 쓰고 경로를 반환한다.
    /// seatbelt 이거나 srt 가 미설치이면 nil.
    static func settingsPath(
        roomDir: String,
        onEvent: (String, RoomEvent) -> Void
    ) -> String? {
        let specURL = URL(fileURLWithPath: roomDir).appendingPathComponent(RoomPaths.specFileName)
        guard FileManager.default.fileExists(atPath: specURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: specURL)
            let spec = try JSONDecoder().decode(RoomSpec.self, from: data)
            guard spec.sandboxBackend == .srt else { return nil }
            guard SRTLaunch.isAvailable else {
                fputs("srt backend requested but srt not found in PATH\n", stderr)
                onEvent(roomDir, RoomEvent(kind: "error", by: "daemon", payload: [
                    "message": .string("srt binary not found — falling back to seatbelt"),
                ]))
                return nil
            }
            let result = SRTSettingsRenderer.render(
                walls: spec.walls,
                workdir: spec.workdir,
                roomDir: roomDir,
                home: NSHomeDirectory()
            )
            return try SRTLaunch.writeSettings(result.settingsJSON, roomDir: roomDir)
        } catch {
            fputs("srt settings render failed: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    /// srt 또는 seatbelt 를 선택하여 PtySandboxConfig 를 반환한다.
    static func sandboxConfig(
        roomDir: String,
        fallbackProfile: String?,
        onEvent: (String, RoomEvent) -> Void
    ) -> PtySandboxConfig {
        let srtPath = settingsPath(roomDir: roomDir, onEvent: onEvent)
        if let srtPath {
            return PtySandboxConfig(srtSettingsPath: srtPath)
        }
        return PtySandboxConfig(seatbeltProfile: fallbackProfile)
    }
}
