import Foundation

public struct MonthlyAmount: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let amount: Decimal
    public let count: Int

    public var id: String { "\(year)-\(month)" }
}

public struct ClientRanking: Hashable, Sendable, Identifiable {
    public let name: String
    public let amount: Decimal
    public let count: Int

    public var id: String { name }
}

extension WorkspaceStore {
    private func kindList(_ kinds: [DocumentKind]) -> (String, [SQLValue]) {
        (Array(repeating: "?", count: kinds.count).joined(separator: ","), kinds.map { .text($0.rawValue) })
    }

    /// Sum of document totals per currency, excluding drafts and cancelled documents.
    public func issuedTotals(kinds: [DocumentKind], since: CalendarDate? = nil) throws -> [CurrencyAmount] {
        let (placeholders, parameters) = kindList(kinds)
        var sql = "SELECT currency, SUM(total_minor) AS amount FROM documents WHERE kind IN (\(placeholders)) AND status NOT IN ('draft','cancelled')"
        var values = parameters
        if let since {
            sql += " AND issue_date >= ?"
            values.append(.text(since.iso))
        }
        sql += " GROUP BY currency ORDER BY amount DESC"
        return try database.query(sql, values).map {
            CurrencyAmount(currency: $0.string("currency") ?? "", amount: Decimal.fromMinorUnits($0.int("amount") ?? 0))
        }
    }

    public func documentCount(kinds: [DocumentKind]? = nil, since: CalendarDate? = nil) throws -> Int {
        var conditions: [String] = []
        var values: [SQLValue] = []
        if let kinds {
            let (placeholders, parameters) = kindList(kinds)
            conditions.append("kind IN (\(placeholders))")
            values += parameters
        }
        if let since {
            conditions.append("issue_date >= ?")
            values.append(.text(since.iso))
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return Int(try database.query("SELECT COUNT(*) AS n FROM documents \(whereClause)", values).first?.int("n") ?? 0)
    }

    /// Issued invoice totals per calendar month in one currency, oldest first, including empty months.
    public func monthlyInvoiced(currency: String, months: Int, endingAt end: CalendarDate = .today) throws -> [MonthlyAmount] {
        var buckets: [(Int, Int)] = []
        var year = end.year
        var month = end.month
        for _ in 0..<months {
            buckets.insert((year, month), at: 0)
            month -= 1
            if month == 0 { month = 12; year -= 1 }
        }
        guard let first = buckets.first else { return [] }
        let start = CalendarDate(year: first.0, month: first.1, day: 1)
        let rows = try database.query("""
        SELECT substr(issue_date, 1, 7) AS ym, SUM(total_minor) AS amount, COUNT(*) AS n FROM documents
        WHERE kind = 'invoice' AND status NOT IN ('draft','cancelled') AND currency = ? AND issue_date >= ?
        GROUP BY ym
        """, [.text(currency), .text(start.iso)])
        var byMonth: [String: (Int64, Int)] = [:]
        for row in rows {
            byMonth[row.string("ym") ?? ""] = (row.int("amount") ?? 0, Int(row.int("n") ?? 0))
        }
        return buckets.map { year, month in
            let key = String(format: "%04d-%02d", year, month)
            let value = byMonth[key] ?? (0, 0)
            return MonthlyAmount(year: year, month: month, amount: Decimal.fromMinorUnits(value.0), count: value.1)
        }
    }

    public func topClients(currency: String, limit: Int = 5) throws -> [ClientRanking] {
        try database.query("""
        SELECT customer_name AS name, SUM(total_minor) AS amount, COUNT(*) AS n FROM documents
        WHERE kind = 'invoice' AND status NOT IN ('draft','cancelled') AND currency = ? AND customer_name != ''
        GROUP BY customer_name ORDER BY amount DESC LIMIT ?
        """, [.text(currency), .int(Int64(limit))]).map {
            ClientRanking(name: $0.string("name") ?? "", amount: Decimal.fromMinorUnits($0.int("amount") ?? 0), count: Int($0.int("n") ?? 0))
        }
    }

    public func statusBreakdown(kind: DocumentKind) throws -> [(DocumentStatus, Int)] {
        try database.query("SELECT status, COUNT(*) AS n FROM documents WHERE kind = ? GROUP BY status ORDER BY n DESC", [.text(kind.rawValue)])
            .compactMap { row in
                guard let status = row.string("status").flatMap(DocumentStatus.init(rawValue:)) else { return nil }
                return (status, Int(row.int("n") ?? 0))
            }
    }
}
