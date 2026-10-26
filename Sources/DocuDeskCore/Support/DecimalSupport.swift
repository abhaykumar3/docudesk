import Foundation

/// Encodes a `Decimal` as a JSON string so money never round-trips through `Double`.
@propertyWrapper
public struct DecimalString: Codable, Hashable, Sendable {
    public var wrappedValue: Decimal

    public init(wrappedValue: Decimal) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard let value = Decimal.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid decimal value '\(text)'")
            }
            wrappedValue = value
        } else {
            // Tolerate plain numbers in hand-edited files; go through the textual form to avoid binary drift.
            let number = try container.decode(Double.self)
            wrappedValue = Decimal(string: String(number), locale: .posix) ?? 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.plainString)
    }
}

extension Locale {
    static let posix = Locale(identifier: "en_US_POSIX")
}

extension Decimal {
    /// Rounds half away from zero (`.plain`) to `scale` fractional digits.
    public func rounded(_ scale: Int = 2, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    /// Locale-independent representation, e.g. `21240.5`.
    public var plainString: String {
        NSDecimalNumber(decimal: self).description(withLocale: Locale.posix)
    }

    /// Value in integer minor units (paise/cents), rounded to two places.
    public var minorUnits: Int64 {
        NSDecimalNumber(decimal: (self * 100).rounded(0)).int64Value
    }

    public static func fromMinorUnits(_ value: Int64) -> Decimal {
        Decimal(value) / 100
    }

    /// Parses user or file input, ignoring grouping separators, spaces and currency symbols.
    public static func parse(_ text: String) -> Decimal? {
        let allowed = Set("0123456789.-")
        let cleaned = String(text.filter { allowed.contains($0) })
        guard !cleaned.isEmpty, cleaned != "-", cleaned != "." else { return nil }
        guard cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        guard cleaned.dropFirst().contains("-") == false else { return nil }
        return Decimal(string: cleaned, locale: .posix)
    }

    public func clamped(_ lower: Decimal, _ upper: Decimal) -> Decimal {
        Swift.min(Swift.max(self, lower), upper)
    }
}
