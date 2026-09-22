import Foundation
import CommandKit
import InteropKit

/// 점유 앱 화면 (F.27) — `agent-ui-monitor see` AX 트리를 패널에 붙인다.
/// 스냅샷 조립 경로에 넣지 않는다. 선택 시에만 호출한다.
public struct OccupancyAX: Sendable {
    private let runner: CommandRunning
    private let cli: String

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        cli: String = HostPlatform.cliBinPath("agent-ui-monitor")
    ) {
        self.runner = runner
        self.cli = cli
    }

    public struct Result: Sendable, Equatable {
        public var ok: Bool
        public var appName: String
        public var text: String
        public init(ok: Bool, appName: String, text: String) {
            self.ok = ok
            self.appName = appName
            self.text = text
        }
    }

    public func see(appName: String) async -> Result {
        let result = await runner.run(
            cli, ["see", "--app", appName, "--no-launch", "--json"], timeout: 8
        )
        let body: String
        if result.ok {
            body = Self.summarize(result.trimmedStdout)
        } else {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            body = err.isEmpty ? "AX 조회 실패 (exit \(result.exitCode))" : err
        }
        return Result(ok: result.ok, appName: appName, text: body)
    }

    /// JSON 전체를 붙이지 않고 창 제목·역할·값만 평문으로.
    static func summarize(_ json: String) -> String {
        guard let data = json.data(using: .utf8) else { return String(json.prefix(4000)) }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return String(json.prefix(4000))
        }
        var lines: [String] = []
        walk(obj, depth: 0, into: &lines)
        if lines.isEmpty { return String(json.prefix(2000)) }
        return lines.prefix(80).joined(separator: "\n")
    }

    private static func walk(_ any: Any, depth: Int, into lines: inout [String]) {
        guard depth < 6, lines.count < 80 else { return }
        if let dict = any as? [String: Any] {
            let role = dict["role"] as? String
            let title = (dict["title"] as? String) ?? (dict["value"] as? String)
            if let role, let title, !title.isEmpty {
                lines.append(String(repeating: "  ", count: depth) + "[\(role)] \(title)")
            }
            if let children = dict["children"] as? [Any] {
                for child in children { walk(child, depth: depth + 1, into: &lines) }
            } else if let result = dict["result"] {
                walk(result, depth: depth, into: &lines)
            }
        } else if let arr = any as? [Any] {
            for item in arr.prefix(20) { walk(item, depth: depth, into: &lines) }
        }
    }
}
