#if canImport(AppKit)
import AppKit
import Foundation
@preconcurrency import SwiftTerm
import TerminalEngineKit

/// `TerminalViewDelegate` 프록시 — URL 오픈 및 클립보드 복사 인터랙션 제어.
@MainActor
final class TerminalInteractionHandler: NSObject, @preconcurrency TerminalViewDelegate {
    weak var originalDelegate: TerminalViewDelegate?
    var onUrlOpened: ((URL) -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onWorkingDirectoryChanged: ((String) -> Void)?
    var onBell: (() -> Void)?

    init(originalDelegate: TerminalViewDelegate?) {
        self.originalDelegate = originalDelegate
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        originalDelegate?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        originalDelegate?.setTerminalTitle(source: source, title: title)
        onTitleChanged?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        originalDelegate?.hostCurrentDirectoryUpdate(source: source, directory: directory)
        if let directory {
            onWorkingDirectoryChanged?(directory)
        }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        originalDelegate?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        originalDelegate?.scrolled(source: source, position: position)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let candidate: URL?
        if trimmed.contains("://") {
            candidate = URL(string: trimmed)
        } else if trimmed.hasPrefix("www.") {
            candidate = URL(string: "https://" + trimmed)
        } else {
            candidate = URL(string: trimmed)
        }

        if let targetURL = candidate {
            NSWorkspace.shared.open(targetURL)
            onUrlOpened?(targetURL)
        }
    }

    func bell(source: TerminalView) {
        originalDelegate?.bell(source: source)
        onBell?()
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        originalDelegate?.clipboardCopy(source: source, content: content)
        if let text = String(bytes: content, encoding: .utf8), !text.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        originalDelegate?.iTermContent(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        originalDelegate?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}

/// 키패스스루 및 상호작용 지원 터미널 뷰
@MainActor
public final class InteractiveTerminalView: LocalProcessTerminalView {
    private var handler: TerminalInteractionHandler?

    public var onUrlOpened: ((URL) -> Void)? {
        get { handler?.onUrlOpened }
        set { handler?.onUrlOpened = newValue }
    }

    public var onTitleChanged: ((String) -> Void)? {
        get { handler?.onTitleChanged }
        set { handler?.onTitleChanged = newValue }
    }

    public var onWorkingDirectoryChanged: ((String) -> Void)? {
        get { handler?.onWorkingDirectoryChanged }
        set { handler?.onWorkingDirectoryChanged = newValue }
    }

    public var onBell: (() -> Void)? {
        get { handler?.onBell }
        set { handler?.onBell = newValue }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupInteractions()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInteractions()
    }

    private func setupInteractions() {
        let h = TerminalInteractionHandler(originalDelegate: self.terminalDelegate)
        self.handler = h
        self.terminalDelegate = h
    }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command,
           let chars = event.charactersIgnoringModifiers,
           let first = chars.first,
           let seq = KittyKeyboardProtocol.cmdDigitSequence(for: first) {
            self.send(txt: seq)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
#endif
