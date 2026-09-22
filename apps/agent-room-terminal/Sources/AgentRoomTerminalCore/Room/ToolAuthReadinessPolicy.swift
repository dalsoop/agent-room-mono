import Foundation

/// 도구별 인증 준비 상태 판정 결과
public enum ToolAuthReadiness: Equatable, Sendable {
    /// 해당 도구는 별도의 인증 시딩/검사가 불필요하거나, 입주 도구가 식별되지 않음
    case notApplicable
    /// 도구 인증 준비 완료 (예: Keychain 자격 증명 시딩 완료)
    case ready(tool: AgentRoomTool)
    /// 도구 인증 미준비 (경고 대상)
    case unready(tool: AgentRoomTool, reason: String)

    /// GUI 상에서 경고 표식이 필요한 상태인지 여부
    public var shouldDisplayWarning: Bool {
        if case .unready = self { return true }
        return false
    }
}

/// 방의 입주 도구를 식별하고, 해당 도구에 맞는 인증 준비 상태를 검사/판정하는 정책 모델
public enum ToolAuthReadinessPolicy {
    /// 특정 도구가 방 환경에서 별도의 인증(Keychain 자격 증명 시딩 등) 검사를 필요로 하는지 판정
    public static func requiresAuthCheck(for tool: AgentRoomTool) -> Bool {
        AgentCredentialInjector.configDirEnvKey(for: tool) != nil
    }

    /// 특정 도구와 방 URL에 대해 인증 준비 상태를 평가
    public static func evaluate(tool: AgentRoomTool, roomURL: URL) -> ToolAuthReadiness {
        guard requiresAuthCheck(for: tool) else {
            return .notApplicable
        }
        let seeded = RoomToolDetector.isCredentialSeeded(tool: tool, roomURL: roomURL)
        if seeded {
            return .ready(tool: tool)
        } else {
            return .unready(tool: tool, reason: "credentials_not_seeded")
        }
    }

    /// 방 URL 및 입주자 목록을 기반으로 입주 도구를 식별하고 인증 준비 상태를 평가
    ///
    /// 입주 도구가 agy, codex, grok 등이거나 식별되지 않는 경우 불필요한 Claude 인증 경고를 억제(.notApplicable 반환)합니다.
    public static func evaluate(
        roomURL: URL,
        occupants: [RoomOccupant]
    ) -> ToolAuthReadiness {
        guard let tool = resolveOccupantTool(roomURL: roomURL, occupants: occupants) else {
            return .notApplicable
        }
        return evaluate(tool: tool, roomURL: roomURL)
    }

    /// 방의 입주 도구를 식별 (spec.json 우선 -> occupants 순)
    /// 식별할 수 없는 경우 임의의 기본값(claude 등)으로 가정하지 않고 nil을 반환
    public static func resolveOccupantTool(
        roomURL: URL?,
        occupants: [RoomOccupant]
    ) -> AgentRoomTool? {
        if let roomURL, let specTool = detectFromSpec(roomURL: roomURL) {
            return specTool
        }
        for occupant in occupants {
            if let tool = RoomToolDetector.parseToolFromHandle(occupant.handle) {
                return tool
            }
        }
        return nil
    }

    private static func detectFromSpec(roomURL: URL) -> AgentRoomTool? {
        RoomToolDetector.detectFromSpec(roomURL: roomURL)
    }
}
