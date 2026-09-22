import Foundation

public enum RoomUsageText {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    public static func format(
        used: Int?,
        limit: Int?,
        estimated: Bool = false,
        unknownText: String = "\u{BBF8}\u{ACC4}\u{CE21}"
    ) -> String {
        guard let used else {
            return unknownText
        }
        let usedStr = formatter.string(from: NSNumber(value: used)) ?? "\(used)"
        let prefix = estimated ? "≈" : ""

        if let limit {
            let limitStr = formatter.string(from: NSNumber(value: limit)) ?? "\(limit)"
            return "\(prefix)\u{D1A0}\u{D070} \(usedStr) / \u{D55C}\u{B3C4} \(limitStr)"
        } else {
            return "\(prefix)\u{D1A0}\u{D070} \(usedStr)"
        }
    }

    public static func format(
        usage: RoomUsage,
        unknownText: String = "\u{BBF8}\u{ACC4}\u{CE21}"
    ) -> String {
        format(
            used: usage.used,
            limit: usage.handoffAt > 0 ? usage.handoffAt : nil,
            estimated: usage.isEstimated,
            unknownText: unknownText
        )
    }
}
