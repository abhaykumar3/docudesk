import Foundation

public enum AmountInWords {
    private static let ones = [
        "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
        "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
    ]
    private static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

    /// `Rupees Twenty-One Thousand Two Hundred Forty Only`.
    public static func words(for amount: Decimal, currency: String) -> String {
        let info = CurrencyInfo.info(for: currency)
        let rounded = amount.rounded(2)
        let negative = rounded < 0
        let magnitude = negative ? -rounded : rounded
        let minorTotal = magnitude.minorUnits
        let major = minorTotal / 100
        let minor = minorTotal % 100

        let majorWords = major == 0 ? "Zero" : spell(major, indian: info.usesIndianNumbering)
        var text: String
        if info.wordsUnitFirst {
            text = "\(info.majorUnit) \(majorWords)"
            if minor > 0 { text += " and \(spell(minor, indian: false)) \(info.minorUnit)" }
        } else {
            text = "\(majorWords) \(info.majorUnit)"
            if minor > 0 { text += " and \(spell(minor, indian: false)) \(info.minorUnit)" }
        }
        return (negative ? "Minus " : "") + text + " Only"
    }

    /// Spells a non-negative whole number.
    public static func spell(_ number: Int64, indian: Bool) -> String {
        guard number > 0 else { return "Zero" }
        return indian ? indianWords(number) : internationalWords(number)
    }

    private static func belowHundred(_ n: Int) -> String {
        if n < 20 { return ones[n] }
        let unit = n % 10
        return unit == 0 ? tens[n / 10] : "\(tens[n / 10])-\(ones[unit])"
    }

    private static func belowThousand(_ n: Int) -> String {
        var parts: [String] = []
        if n >= 100 { parts.append("\(ones[n / 100]) Hundred") }
        if n % 100 > 0 { parts.append(belowHundred(n % 100)) }
        return parts.joined(separator: " ")
    }

    private static func indianWords(_ number: Int64) -> String {
        var parts: [String] = []
        let crore = number / 10_000_000
        let lakh = Int((number / 100_000) % 100)
        let thousand = Int((number / 1_000) % 100)
        let rest = Int(number % 1_000)
        if crore > 0 { parts.append("\(indianWords(crore)) Crore") }
        if lakh > 0 { parts.append("\(belowHundred(lakh)) Lakh") }
        if thousand > 0 { parts.append("\(belowHundred(thousand)) Thousand") }
        if rest > 0 { parts.append(belowThousand(rest)) }
        return parts.joined(separator: " ")
    }

    private static func internationalWords(_ number: Int64) -> String {
        let scales: [(Int64, String)] = [
            (1_000_000_000_000, "Trillion"), (1_000_000_000, "Billion"), (1_000_000, "Million"), (1_000, "Thousand"),
        ]
        var remaining = number
        var parts: [String] = []
        for (value, name) in scales where remaining >= value {
            parts.append("\(internationalWords(remaining / value)) \(name)")
            remaining %= value
        }
        if remaining > 0 { parts.append(belowThousand(Int(remaining))) }
        return parts.joined(separator: " ")
    }
}
