import Foundation

/// 테넌트 경계 밖 파일 쓰기 등 정책 위반 지점 모델.
public struct TenantViolation: Codable, Equatable, Sendable {
    public var path: String
    public var operation: String // "write", "network", "exec"
    public var reason: String

    public init(path: String, operation: String = "write", reason: String) {
        self.path = path
        self.operation = operation
        self.reason = reason
    }
}
