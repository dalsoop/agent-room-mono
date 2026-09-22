#if canImport(AppKit)
import AppKit
import SwiftTerm
import TerminalEngineKit

/// `TerminalAppearance`(폰트+테마)를 SwiftTerm 뷰에 적용한다.
@MainActor
public enum TerminalAppearanceApplier {
    public static func apply(_ ap: TerminalAppearance, to view: LocalProcessTerminalView) {
        let size = CGFloat(ap.fontSize)
        let primaryFont = NSFont(name: ap.fontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)

        let fallbackName = ap.fallbackFontName ?? "Apple SD Gothic Neo"
        if let fallbackFont = NSFont(name: fallbackName, size: size) {
            let descriptor = primaryFont.fontDescriptor.addingAttributes([
                .cascadeList: [fallbackFont.fontDescriptor]
            ])
            view.font = NSFont(descriptor: descriptor, size: size) ?? primaryFont
        } else {
            view.font = primaryFont
        }
        view.optionAsMetaKey = ap.macosOptionAsAlt

        let theme = TerminalThemes.theme(ap.themeID)
        if theme.usesNativeColors {
            view.configureNativeColors()
        } else {
            if let bg = theme.bg { view.nativeBackgroundColor = nsColor(bg) }
            if let fg = theme.fg { view.nativeForegroundColor = nsColor(fg) }
            if let c = theme.cursor { view.caretColor = nsColor(c) }
            if theme.ansi.count == 16 { view.installColors(theme.ansi.map(termColor)) }
        }
    }

    public static func nsColor(_ c: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                blue: CGFloat(c.b) / 255, alpha: 1)
    }

    public static func termColor(_ c: RGB) -> SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(c.r) * 257, green: UInt16(c.g) * 257, blue: UInt16(c.b) * 257)
    }
}
#endif
