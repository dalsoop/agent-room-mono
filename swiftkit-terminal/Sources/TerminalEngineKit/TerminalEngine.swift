#if canImport(AppKit)
import AppKit
public typealias TerminalPlatformView = NSView
#elseif canImport(UIKit)
import UIKit
public typealias TerminalPlatformView = UIView
#endif
import Foundation

/// 터미널 렌더링 및 PTY 프로세스를 제어하는 엔진 추상 인터페이스.
/// SwiftTerm, GhosttyKit, Mock 엔진 등이 이 프로토콜을 구현한다.
@MainActor
public protocol TerminalEngine: AnyObject {
    /// 뷰 계층에 올릴 터미널 뷰
    var view: TerminalPlatformView { get }

    /// PTY 프로세스 시작 (중복 호출 시 안전하게 no-op)
    func startIfNeeded()

    /// 프로세스 종료 또는 뷰 내림
    func terminate()

    /// 폰트, 테마 등 외형 적용
    func applyAppearance(_ appearance: TerminalAppearance)

    /// 키보드 포커스 요청 (first responder)
    func makeFirstResponder()

    /// 뷰 숨김 여부 (창 비가시성 시 CPU 절전용)
    var isViewHidden: Bool { get set }

    /// 좌표 히트 테스트 (마우스 클릭 감지용)
    func containsPointInWindow(_ point: CGPoint) -> Bool

    /// 터미널 PTY 세션으로 직접 텍스트/키 시퀀스 전송
    func send(text: String)

    /// PTY 프로세스가 종료(exit/Ctrl+D)되었을 때 호출되는 콜백
    var onProcessTerminated: (() -> Void)? { get set }

    /// 터미널 라이프사이클 및 제어 이벤트 수신 델리게이트
    var eventsDelegate: (any TerminalEngineEvents)? { get set }
}

extension TerminalEngine {
    public var onProcessTerminated: (() -> Void)? {
        get { nil }
        set {}
    }

    public var eventsDelegate: (any TerminalEngineEvents)? {
        get { nil }
        set {}
    }
}

/// 단위 테스트 및 SwiftUI 프리뷰를 위한 가상 터미널 엔진.
@MainActor
open class MockTerminalEngine: TerminalEngine {
    public let mockView: TerminalPlatformView
    public private(set) var startCount = 0
    public private(set) var terminateCount = 0
    public private(set) var appearances: [TerminalAppearance] = []
    public private(set) var madeFirstResponderCount = 0
    public private(set) var sentTexts: [String] = []
    public var isViewHidden: Bool = false
    public var onProcessTerminated: (() -> Void)?
    public weak var eventsDelegate: (any TerminalEngineEvents)?

    public var view: TerminalPlatformView { mockView }

    public func simulateProcessExit(exitCode: Int = 0) {
        eventsDelegate?.terminalProcessDidTerminate(exitCode: exitCode)
        onProcessTerminated?()
    }

    public init(view: TerminalPlatformView = TerminalPlatformView(frame: .zero)) {
        self.mockView = view
    }

    open func startIfNeeded() {
        startCount += 1
    }

    open func terminate() {
        terminateCount += 1
    }

    open func applyAppearance(_ appearance: TerminalAppearance) {
        appearances.append(appearance)
    }

    open func makeFirstResponder() {
        madeFirstResponderCount += 1
    }

    open func containsPointInWindow(_ point: CGPoint) -> Bool {
        #if canImport(AppKit)
        guard mockView.window != nil, !mockView.isHiddenOrHasHiddenAncestor else {
            return false
        }
        return mockView.bounds.contains(mockView.convert(point, from: nil))
        #else
        guard mockView.window != nil, !mockView.isHidden else {
            return false
        }
        return mockView.bounds.contains(mockView.convert(point, from: nil))
        #endif
    }

    open func send(text: String) {
        sentTexts.append(text)
    }
}

// 하위 호환 별칭
public typealias TerminalEngineSession = TerminalEngine
public typealias MockTerminalEngineSession = MockTerminalEngine
