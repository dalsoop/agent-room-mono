import Foundation
import LocalizationKit

/// 방 이름 게이트 — 경로·테넌트 id·공백을 handle 에 쓰지 못하게 한다.
public enum RoomHandleGate {
    public static func reason(_ handle: String) -> String? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return CLILocalization.string("RoomHandleGate.return") }
        if trimmed.count > 40 { return CLILocalization.string("RoomHandleGate.return-2") }
        if trimmed.contains("/") || trimmed.contains("\\") { return "handle 에 경로 구분자가 있다" }
        if trimmed.hasPrefix("tenant:") { return "handle 은 테넌트 id 가 아니다" }
        return nil
    }

    public static func isValid(_ handle: String) -> Bool { reason(handle) == nil }
}
