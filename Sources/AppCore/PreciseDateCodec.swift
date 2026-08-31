import Foundation

/// RFC 3339 UTC timestamps with nine fractional digits. Nine digits preserve
/// the full practical precision of Foundation `Date` at current epochs, unlike
/// `ISO8601DateFormatter`'s millisecond-only output on Apple platforms.
public enum PreciseDateCodec {
    public static func string(from date: Date) -> String {
        var wholeSeconds = floor(date.timeIntervalSince1970)
        var nanoseconds = Int(
            ((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded()
        )
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let whole = formatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
        guard whole.hasSuffix("Z") else { return whole }
        return "\(whole.dropLast()).\(String(format: "%09d", nanoseconds))Z"
    }

    public static func date(from rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if let dot = rawValue.lastIndex(of: "."), rawValue.hasSuffix("Z") {
            let fractionStart = rawValue.index(after: dot)
            let fractionEnd = rawValue.index(before: rawValue.endIndex)
            let fraction = rawValue[fractionStart..<fractionEnd]
            guard
                !fraction.isEmpty,
                fraction.count <= 9,
                fraction.allSatisfy(\.isNumber),
                let base = formatter.date(from: "\(rawValue[..<dot])Z")
            else {
                return nil
            }
            let paddedFraction = fraction + String(repeating: "0", count: 9 - fraction.count)
            guard let nanoseconds = Int(paddedFraction) else { return nil }
            return base.addingTimeInterval(Double(nanoseconds) / 1_000_000_000)
        }

        return formatter.date(from: rawValue)
    }
}
