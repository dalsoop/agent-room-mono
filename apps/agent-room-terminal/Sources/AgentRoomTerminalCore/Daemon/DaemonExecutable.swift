import Foundation

public enum DaemonExecutable {
    public static let fileName = "agent-room-terminal-daemon"
    public static let pathEnvironmentKey = "AGENT_ROOM_TERMINAL_DAEMON"

    public static func locate(
        override: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> URL? {
        if let override {
            return override
        }
        if let envPath = environment[pathEnvironmentKey], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        let helpers = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: helpers.path) {
            return helpers
        }
        for directory in siblingDirectories(environment: environment, arguments: arguments) {
            let sibling = directory.appendingPathComponent(fileName, isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: sibling.path) {
                return sibling
            }
        }
        return nil
    }

    /// CLI 와 "같은 디렉터리" 후보. PATH 로 호출되면 argv[0] 에 디렉터리가 없으므로
    /// 실행 파일 실경로(심링크 해석 전·후)와 PATH 탐색 결과를 모두 본다.
    static func siblingDirectories(
        environment: [String: String],
        arguments: [String]
    ) -> [URL] {
        var directories: [URL] = []
        if let executable = Bundle.main.executableURL {
            directories.append(executable.deletingLastPathComponent())
            directories.append(executable.resolvingSymlinksInPath().deletingLastPathComponent())
        }
        guard let argv0 = arguments.first else { return directories }
        if argv0.contains("/") {
            directories.append(URL(fileURLWithPath: argv0).deletingLastPathComponent())
            return directories
        }
        if let found = pathLookup(argv0, environment: environment) {
            directories.append(found.deletingLastPathComponent())
        }
        return directories
    }

    static func pathLookup(_ name: String, environment: [String: String]) -> URL? {
        let path = environment["PATH"] ?? ""
        for entry in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry), isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
