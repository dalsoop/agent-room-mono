import Foundation

/// 진행률 표시 상태 (OSC 9;4 / DECSET progress report)
public enum TerminalProgressState: Sendable, Equatable {
    case remove
    case set
    case error
    case indeterminate
    case pause
}

/// 터미널 렌더러 및 프로세스 이벤트 델리게이트 단일 정본.
@MainActor
public protocol TerminalEngineEvents: AnyObject {
    /// 윈도우/탭 타이틀 변경 (OSC 0/2)
    func terminalDidChangeTitle(_ title: String)

    /// 작업 디렉터리 변경 (OSC 7)
    func terminalDidChangeWorkingDirectory(_ path: String)

    /// 터미널 벨 울림 (BEL, \a)
    func terminalDidRingBell()

    /// 진행률 보고 (OSC 9;4)
    func terminalDidReportProgress(state: TerminalProgressState, percent: Int?)

    /// 셸 통합 명령 실행 완료
    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64)

    /// 데스크톱 알림 요청 (OSC 9 / OSC 777)
    func terminalDidRequestDesktopNotification(title: String, body: String)

    /// PTY/자식 프로세스 종료
    func terminalProcessDidTerminate(exitCode: Int?)

    /// 서피스 닫힘 (하위 호환)
    func terminalDidClose(processAlive: Bool)
}

extension TerminalEngineEvents {
    public func terminalDidChangeTitle(_ title: String) {}
    public func terminalDidChangeWorkingDirectory(_ path: String) {}
    public func terminalDidRingBell() {}
    public func terminalDidReportProgress(state: TerminalProgressState, percent: Int?) {}
    public func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {}
    public func terminalDidRequestDesktopNotification(title: String, body: String) {}
    public func terminalProcessDidTerminate(exitCode: Int?) {}
    public func terminalDidClose(processAlive: Bool) {
        terminalProcessDidTerminate(exitCode: nil)
    }
}
