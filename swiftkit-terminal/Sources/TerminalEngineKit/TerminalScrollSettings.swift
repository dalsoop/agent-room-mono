import Foundation

/// 내장 터미널의 스크롤 동작 설정. tmux 옵션으로 투영되며 UserDefaults 로 저장된다.
///
/// - `mouse on`  : 휠이 tmux 로 간다(pane 클릭 선택·copy-mode 스크롤 가능).
/// - `alternateScroll` : alt-screen(TUI)에서 휠을 방향키로 바꿔 앱에 전달.
/// - `showScrollbars` : pane 에 스크롤바 표시(tmux 3.4+ `pane-scrollbars`).
/// - `history-limit` : tmux 스크롤백 줄 수(세션 생성 시점에 고정).
/// - `wheelLines` : 휠 한 칸당 넘길 줄 수.
public struct TerminalScrollSettings: Sendable, Equatable, Codable {
    /// tmux 가 마우스를 잡는가.
    public var mouseOn: Bool
    /// alt-screen 에서 휠 → 방향키 변환.
    public var alternateScroll: Bool
    /// pane 스크롤바 표시.
    public var showScrollbars: Bool
    /// tmux 스크롤백 줄 수.
    public var historyLimit: Int
    /// 휠 한 칸당 스크롤 줄 수.
    public var wheelLines: Int

    public init(mouseOn: Bool = true, alternateScroll: Bool = true,
                showScrollbars: Bool = false,
                historyLimit: Int = 50_000, wheelLines: Int = 3) {
        self.mouseOn = mouseOn
        self.alternateScroll = alternateScroll
        self.showScrollbars = showScrollbars
        self.historyLimit = Self.clampHistory(historyLimit)
        self.wheelLines = Self.clampWheel(wheelLines)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mouseOn: try c.decodeIfPresent(Bool.self, forKey: .mouseOn) ?? true,
            alternateScroll: try c.decodeIfPresent(Bool.self, forKey: .alternateScroll) ?? true,
            showScrollbars: try c.decodeIfPresent(Bool.self, forKey: .showScrollbars) ?? false,
            historyLimit: try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 50_000,
            wheelLines: try c.decodeIfPresent(Int.self, forKey: .wheelLines) ?? 3)
    }

    public static let `default` = TerminalScrollSettings()

    // 클램프 범위
    public static let minHistory = 1_000
    public static let maxHistory = 500_000
    public static let minWheelLines = 1
    public static let maxWheelLines = 20

    public static func clampHistory(_ v: Int) -> Int { min(maxHistory, max(minHistory, v)) }
    public static func clampWheel(_ v: Int) -> Int { min(maxWheelLines, max(minWheelLines, v)) }

    /// tmux config 로 투영되는 줄들
    public var configLines: [String] {
        var lines = [
            "set -g mouse \(mouseOn ? "on" : "off")",
            "set -g history-limit \(historyLimit)",
            "setw -gq pane-scrollbars \(showScrollbars ? "on" : "off")",
        ]
        for table in ["copy-mode", "copy-mode-vi"] {
            lines.append("bind -T \(table) WheelUpPane send -N\(wheelLines) -X scroll-up")
            lines.append("bind -T \(table) WheelDownPane send -N\(wheelLines) -X scroll-down")
        }
        if alternateScroll {
            lines.append("bind -n WheelUpPane if -Ft= '#{?pane_in_mode,1,#{alternate_on}}' "
                + "'send -N\(wheelLines) Up' 'copy-mode -e; send -M'")
            lines.append("bind -n WheelDownPane if -Ft= '#{?pane_in_mode,1,#{alternate_on}}' "
                + "'send -N\(wheelLines) Down' 'send -M'")
        } else {
            lines.append("unbind -n -q WheelUpPane")
            lines.append("unbind -n -q WheelDownPane")
        }
        return lines
    }

    /// 저장된 설정 로드 (suiteName/key 커스텀 지원)
    public static func load(suiteName: String? = nil, key: String = "terminal.scroll") -> TerminalScrollSettings {
        let d = suiteName != nil ? UserDefaults(suiteName: suiteName) : UserDefaults.standard
        guard let d,
              let data = d.data(forKey: key),
              let s = try? JSONDecoder().decode(TerminalScrollSettings.self, from: data)
        else { return .default }
        return s
    }

    /// 설정 저장 (suiteName/key 커스텀 지원)
    public func save(suiteName: String? = nil, key: String = "terminal.scroll") {
        let d = suiteName != nil ? UserDefaults(suiteName: suiteName) : UserDefaults.standard
        guard let d,
              let data = try? JSONEncoder().encode(self) else { return }
        d.set(data, forKey: key)
    }

    /// tmux config 기본 경로 (appDirectory 커스텀 지원)
    public static func defaultConfigPath(appDirectory: String = "terminal") -> String {
        NSHomeDirectory() + "/.config/\(appDirectory)/tmux.conf"
    }

    /// 살아있는 tmux 서버에 config 를 다시 읽히는 인자 (`tmux -L <socket> source-file <path>`)
    public static func sourceFileArgs(socket: String, config: String) -> [String] {
        ["-L", socket, "source-file", config]
    }
}
