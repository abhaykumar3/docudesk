import Foundation

public struct CurrencyInfo: Hashable, Sendable, Identifiable {
    public let code: String
    public let name: String
    public let majorUnit: String
    public let minorUnit: String
    /// Indian grouping and wording (lakh/crore) instead of million/billion.
    public let usesIndianNumbering: Bool
    /// "Rupees One Hundred Only" vs "One Hundred US Dollars Only".
    public let wordsUnitFirst: Bool
    let localeID: String

    public var id: String { code }

    public static let supported: [CurrencyInfo] = [
        CurrencyInfo(code: "INR", name: "Indian Rupee", majorUnit: "Rupees", minorUnit: "Paise", usesIndianNumbering: true, wordsUnitFirst: true, localeID: "en_IN"),
        CurrencyInfo(code: "USD", name: "US Dollar", majorUnit: "US Dollars", minorUnit: "Cents", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_US"),
        CurrencyInfo(code: "EUR", name: "Euro", majorUnit: "Euros", minorUnit: "Cents", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_IE"),
        CurrencyInfo(code: "GBP", name: "British Pound", majorUnit: "Pounds", minorUnit: "Pence", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_GB"),
        CurrencyInfo(code: "AED", name: "UAE Dirham", majorUnit: "Dirhams", minorUnit: "Fils", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_AE"),
        CurrencyInfo(code: "AUD", name: "Australian Dollar", majorUnit: "Australian Dollars", minorUnit: "Cents", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_AU"),
        CurrencyInfo(code: "CAD", name: "Canadian Dollar", majorUnit: "Canadian Dollars", minorUnit: "Cents", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_CA"),
        CurrencyInfo(code: "SGD", name: "Singapore Dollar", majorUnit: "Singapore Dollars", minorUnit: "Cents", usesIndianNumbering: false, wordsUnitFirst: false, localeID: "en_SG"),
    ]

    public static func info(for code: String) -> CurrencyInfo {
        supported.first { $0.code == code }
            ?? CurrencyInfo(code: code, name: code, majorUnit: code, minorUnit: "Cents", usesIndianNumbering: false, wordsUnitFirst: true, localeID: "en_US")
    }
}

public enum MoneyFormatter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NumberFormatter] = [:]

    private static func formatter(for code: String, symbol: Bool) -> NumberFormatter {
        let key = "\(code)|\(symbol)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let info = CurrencyInfo.info(for: code)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: info.localeID)
        formatter.numberStyle = symbol ? .currency : .decimal
        formatter.currencyCode = code
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        cache[key] = formatter
        return formatter
    }

    /// `₹21,240.00`, `$1,050.00`.
    public static func format(_ amount: Decimal, currency: String) -> String {
        let formatter = formatter(for: currency, symbol: true)
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(currency) \(amount.plainString)"
    }

    /// Grouped number without a symbol, for table cells: `21,240.00`.
    public static func number(_ amount: Decimal, currency: String) -> String {
        let formatter = formatter(for: currency, symbol: false)
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? amount.plainString
    }

    /// Quantities and rates: up to three decimals with no trailing zeros.
    public static func quantity(_ value: Decimal) -> String {
        let rounded = value.rounded(3)
        return rounded.plainString
    }
}
