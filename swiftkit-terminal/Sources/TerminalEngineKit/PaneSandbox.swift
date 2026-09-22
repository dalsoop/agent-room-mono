import Foundation
import StateRootKit
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit.terminal", category: "PaneSandbox")

/// pane 하나 = **독립 실행 공간** 메타데이터.
///
/// - 각 pane 은 고유 `paneId` 와 전용 홈 디렉터리를 갖는다.
/// - 에이전트 계정 격리는 handoff 와 동일 계약: **전역 switch 금지**, config-dir env 만.
/// - 소통(브로드캐스트·peer 버스)은 이 공간 **위에서** 이뤄진다 — sandbox 가 먼저 분리.
public struct PaneSandbox: Sendable, Equatable, Codable {
    public static let defaultRootDirName = ".terminal/panes"
    public static let defaultEnvPaneID = "TERMINAL_PANE_ID"
    public static let defaultEnvPaneHome = "TERMINAL_PANE_HOME"

    /// 세션 이름 뒤쪽 짧은 id 또는 UUID 접두.
    public var paneId: String
    /// 전용 홈(작업 메모·inbox 등).
    public var homePath: String
    /// PTY/셸에 주입할 추가 env (격리 포함).
    public var environment: [String: String]
    /// UI 배지용 — "Claude · team@…" 등.
    public var label: String?
    /// 격리 대상 툴(있으면).
    public var toolRaw: String?
    /// 계정 라벨(있으면).
    public var accountLabel: String?

    public init(
        paneId: String,
        homePath: String,
        environment: [String: String] = [:],
        label: String? = nil,
        toolRaw: String? = nil,
        accountLabel: String? = nil
    ) {
        self.paneId = paneId
        self.homePath = homePath
        self.environment = environment
        self.label = label
        self.toolRaw = toolRaw
        self.accountLabel = accountLabel
    }

    /// 기본 sandbox — id + 전용 홈만.
    public static func make(
        paneId: String,
        rootDirName: String = defaultRootDirName,
        envPaneIDKey: String = defaultEnvPaneID,
        envPaneHomeKey: String = defaultEnvPaneHome,
        fileManager: FileManager = .default
    ) -> PaneSandbox {
        let root = StateRootKit.path(rootDirName)
        let home = (root as NSString).appendingPathComponent(paneId)
        do {
            try fileManager.createDirectory(atPath: home, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                atPath: (home as NSString).appendingPathComponent("inbox"),
                withIntermediateDirectories: true)
        } catch {
            logger.error("createDirectory failed for \(home, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        let env: [String: String] = [
            envPaneIDKey: paneId,
            envPaneHomeKey: home,
        ]
        return PaneSandbox(
            paneId: paneId,
            homePath: home,
            environment: env,
            label: "pane \(paneId)"
        )
    }

    /// `export A=B; export C=D` 형태(셸 -c 앞에 붙임).
    public var exportPrefix: String {
        environment
            .sorted { $0.key < $1.key }
            .map { "export \($0.key)=\(Self.shellQuote($0.value))" }
            .joined(separator: "; ")
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 세션 이름 → paneId.
    public static func paneId(fromSessionName name: String, prefix: String = "terminal/") -> String {
        if name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name.replacingOccurrences(of: "/", with: "-")
    }

    public static func paneId(fromTmuxName name: String, prefix: String = "terminal/") -> String {
        paneId(fromSessionName: name, prefix: prefix)
    }
}
