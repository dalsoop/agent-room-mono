import Foundation

/// 0–255 RGB (플랫폼 색 타입 비의존 — AppKit/UIKit 등에서 변환).
public struct RGB: Sendable, Equatable, Codable {
    public let r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    /// "#rrggbb" 또는 "rrggbb".
    public init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
    }
}

/// 터미널 색 테마. `usesNativeColors` 면 시스템 텍스트 색을 따른다(라이트/다크 자동).
public struct TerminalTheme: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let usesNativeColors: Bool
    public let fg: RGB?
    public let bg: RGB?
    public let cursor: RGB?
    public let ansi: [RGB]     // 16색(비어 있으면 엔진 기본 유지)

    public init(id: String, name: String, usesNativeColors: Bool = false,
                fg: RGB? = nil, bg: RGB? = nil, cursor: RGB? = nil, ansi: [RGB] = []) {
        self.id = id; self.name = name; self.usesNativeColors = usesNativeColors
        self.fg = fg; self.bg = bg; self.cursor = cursor; self.ansi = ansi
    }
}

/// 터미널 외형 설정(폰트 + 테마 + 키보드 옵션).
public struct TerminalAppearance: Sendable, Equatable, Codable {
    public var fontName: String
    public var fontSize: Double
    public var themeID: String
    public var fallbackFontName: String?
    public var macosOptionAsAlt: Bool

    public init(
        fontName: String = "Menlo",
        fontSize: Double = 13,
        themeID: String = "system",
        fallbackFontName: String? = "Apple SD Gothic Neo",
        macosOptionAsAlt: Bool = true
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.themeID = themeID
        self.fallbackFontName = fallbackFontName
        self.macosOptionAsAlt = macosOptionAsAlt
    }

    public static let `default` = TerminalAppearance()

    enum CodingKeys: String, CodingKey {
        case fontName
        case fontSize
        case themeID
        case fallbackFontName
        case macosOptionAsAlt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "Menlo"
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        self.themeID = try container.decodeIfPresent(String.self, forKey: .themeID) ?? "system"
        self.fallbackFontName = try container.decodeIfPresent(String.self, forKey: .fallbackFontName) ?? "Apple SD Gothic Neo"
        self.macosOptionAsAlt = try container.decodeIfPresent(Bool.self, forKey: .macosOptionAsAlt) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(themeID, forKey: .themeID)
        try container.encodeIfPresent(fallbackFontName, forKey: .fallbackFontName)
        try container.encode(macosOptionAsAlt, forKey: .macosOptionAsAlt)
    }

    /// 폰트 크기 클램프 범위.
    public static let minSize: Double = 8
    public static let maxSize: Double = 28

    public func withSize(_ s: Double) -> TerminalAppearance {
        var c = self
        c.fontSize = min(Self.maxSize, max(Self.minSize, s))
        return c
    }

    public func withOptionAsAlt(_ enabled: Bool) -> TerminalAppearance {
        var c = self; c.macosOptionAsAlt = enabled; return c
    }
}

public enum TerminalThemes {
    /// 고를 수 있는 monospace 폰트 목록.
    public static let fontChoices = ["Menlo", "SF Mono", "Monaco", "Courier New", "Andale Mono"]

    public static let all: [TerminalTheme] = [
        TerminalTheme(id: "system", name: "System", usesNativeColors: true),
        TerminalTheme(id: "dark", name: "Dark",
                      fg: RGB(hex: "#d4d4d4"), bg: RGB(hex: "#1e1e1e"), cursor: RGB(hex: "#ffffff")),
        TerminalTheme(id: "light", name: "Light",
                      fg: RGB(hex: "#1e1e1e"), bg: RGB(hex: "#fafafa"), cursor: RGB(hex: "#000000")),
        TerminalTheme(id: "solarized-dark", name: "Solarized Dark",
                      fg: RGB(hex: "#839496"), bg: RGB(hex: "#002b36"), cursor: RGB(hex: "#93a1a1"),
                      ansi: [
                        RGB(hex: "#073642")!, RGB(hex: "#dc322f")!, RGB(hex: "#859900")!, RGB(hex: "#b58900")!,
                        RGB(hex: "#268bd2")!, RGB(hex: "#d33682")!, RGB(hex: "#2aa198")!, RGB(hex: "#eee8d5")!,
                        RGB(hex: "#002b36")!, RGB(hex: "#cb4b16")!, RGB(hex: "#586e75")!, RGB(hex: "#657b83")!,
                        RGB(hex: "#839496")!, RGB(hex: "#6c71c4")!, RGB(hex: "#93a1a1")!, RGB(hex: "#fdf6e3")!,
                      ]),
    ]

    /// id 로 테마 찾기(없으면 시스템). 대소문자 및 변형 허용.
    public static func theme(_ id: String) -> TerminalTheme {
        let normalized = id.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = all.first(where: { $0.id.lowercased() == normalized }) {
            return exact
        }
        let isSolarizedDark = normalized.contains("solarized") && normalized.contains("dark")
        let isSolarized = (normalized == "solarized")
        if isSolarizedDark || isSolarized {
            return theme("solarized-dark")
        }
        if normalized.contains("dark") {
            return theme("dark")
        }
        if normalized.contains("light") {
            return theme("light")
        }
        return all[0]
    }
}
