import Foundation

/// A calendar day with no time or time zone, so issue and due dates never shift
/// when the system time zone or clock changes.
public struct CalendarDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public static var today: CalendarDate { CalendarDate(Date()) }

    /// Midday in the current time zone, which is safe to hand to date pickers.
    public var date: Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return Calendar.current.date(from: parts) ?? Date()
    }

    public func adding(days: Int) -> CalendarDate {
        CalendarDate(Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    public func days(until other: CalendarDate) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    /// Display form used on documents, e.g. `26 Oct 2026`.
    public var display: String {
        CalendarDate.displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = CalendarDate(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date '\(text)'")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
