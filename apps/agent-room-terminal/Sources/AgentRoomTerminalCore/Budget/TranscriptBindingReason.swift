import Foundation

/// `TranscriptBinding.reason` 값. 추정 경로를 만들지 않고 이 셋만 쓴다.
public enum TranscriptBindingReason {
    public static let resolved = "resolved"
    public static let noRule = "noRule"
    public static let toolUnsupported = "toolUnsupported"
}

/// 예산 `unknown` 에 붙는 이유.
public enum UnknownBudgetReason {
    public static let noBinding = "noBinding"
    public static let noTranscript = "noTranscript"
    public static let toolUnsupported = "toolUnsupported"
}

/// 이미 떠 있는 프로세스에는 seatbelt 를 씌울 수 없다.
public enum WallEnforcementScope {
    public static let wallsRegisteredOnly = "walls-registered-only"
    public static let fileName = "wall-enforcement.json"
    public static let wallModeFull = "full"
}
