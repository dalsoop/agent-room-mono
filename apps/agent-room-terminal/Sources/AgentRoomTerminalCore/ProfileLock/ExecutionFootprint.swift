import Foundation

/// 실행 중 관찰된 파일, 네트워크, 자식 프로세스 발자국.
public struct ExecutionFootprint: Codable, Equatable, Sendable {
    public var argv: [String]
    public var exitCode: Int
    public var durationMs: Int
    public var fileReads: [String]
    public var fileWrites: [String]
    public var networkOutbound: [String]
    public var childProcesses: [String]
    public var workingDirectory: String?
    public var timestamp: Date

    public init(
        argv: [String] = [],
        exitCode: Int = 0,
        durationMs: Int = 0,
        fileReads: [String] = [],
        fileWrites: [String] = [],
        networkOutbound: [String] = [],
        childProcesses: [String] = [],
        workingDirectory: String? = nil,
        timestamp: Date = Date()
    ) {
        self.argv = argv
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.fileReads = Array(Set(fileReads)).sorted()
        self.fileWrites = Array(Set(fileWrites)).sorted()
        self.networkOutbound = Array(Set(networkOutbound)).sorted()
        self.childProcesses = Array(Set(childProcesses)).sorted()
        self.workingDirectory = workingDirectory
        self.timestamp = timestamp
    }
}
