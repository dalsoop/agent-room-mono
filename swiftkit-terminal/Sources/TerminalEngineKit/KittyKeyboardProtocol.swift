import Foundation

/// Kitty 키보드 프로토콜 시퀀스 생성 및 키 매핑 유틸리티.
public enum KittyKeyboardProtocol {
    /// Cmd+<1...9> 에 대응하는 Kitty 키보드 프로토콜 시퀀스 반환.
    /// 예: digit 1 -> "\u{1b}[49;9u" (keybind = cmd+1=text:\x1b[49;9u 와 동일)
    public static func cmdDigitSequence(_ digit: Int) -> String? {
        guard (1...9).contains(digit) else { return nil }
        return "\u{1b}[\(48 + digit);9u"
    }

    /// Character ("1"..."9") 에 대응하는 Kitty 키 시퀀스 반환.
    public static func cmdDigitSequence(for character: Character) -> String? {
        guard let digit = character.wholeNumberValue, (1...9).contains(digit) else {
            return nil
        }
        return cmdDigitSequence(digit)
    }
}
