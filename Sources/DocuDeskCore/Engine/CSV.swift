import Foundation

/// RFC 4180 CSV parsing (quoted fields, escaped quotes, embedded commas and newlines).
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty:
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n":
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// Rows as dictionaries keyed by normalised header (`"Postal Code"` → `"postal_code"`).
    public static func records(_ text: String) -> (headers: [String], rows: [[String: String]]) {
        let table = parse(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = table.first else { return ([], []) }
        let keys = header.map { CustomFieldDefinition.key(for: $0.trimmingCharacters(in: .whitespaces)) }
        let rows = table.dropFirst().map { values in
            var record: [String: String] = [:]
            for (index, key) in keys.enumerated() where index < values.count {
                record[key] = values[index].trimmingCharacters(in: .whitespaces)
            }
            return record
        }
        return (keys, rows)
    }
}

/// One generated document's recipient, from saved clients or a CSV row.
public struct BulkRecipient: Hashable, Sendable {
    public var party: PartyDetails
    public var customerID: UUID?
    /// Extra columns, available as `{{field.<column>}}` and as custom-field values.
    public var fields: [String: String]

    public init(party: PartyDetails, customerID: UUID? = nil, fields: [String: String] = [:]) {
        self.party = party
        self.customerID = customerID
        self.fields = fields
    }

    public init(customer: Customer) {
        self.init(party: customer.party, customerID: customer.id)
    }

    public static var partyColumnKeys: Set<String> { partyColumns }

    static let partyColumns: Set<String> = [
        "name", "client", "client_name", "company", "customer", "contact", "contact_person", "email", "phone", "mobile",
        "address", "address_line_1", "line1", "address_line_2", "line2", "city", "state", "postal_code", "pin", "pincode", "zip",
        "country", "gstin", "tax_id", "vat",
    ]

    /// Maps common column names onto client details; everything else becomes a field.
    public init(record: [String: String]) {
        func value(_ keys: String...) -> String {
            keys.lazy.compactMap { record[$0] }.first { !$0.isEmpty } ?? ""
        }
        var party = PartyDetails(name: value("name", "client", "client_name", "company", "customer"))
        party.contactPerson = value("contact", "contact_person")
        party.email = value("email")
        party.phone = value("phone", "mobile")
        party.taxID = value("gstin", "tax_id", "vat")
        party.billingAddress = Address(line1: value("address", "address_line_1", "line1"), line2: value("address_line_2", "line2"),
                                       city: value("city"), state: value("state"), postalCode: value("postal_code", "pin", "pincode", "zip"),
                                       country: value("country"))
        let extra = record.filter { !Self.partyColumns.contains($0.key) && !$0.value.isEmpty }
        self.init(party: party, fields: extra)
    }
}

public struct BulkOptions: Sendable {
    public var issueDate: CalendarDate = .today
    public var issue = false
    /// When set, a PDF of every generated document is written here.
    public var exportFolder: URL?
    public var saveNewClients = false

    public init() {}
}

public struct BulkResult: Sendable {
    public var created: [DocumentRecord] = []
    public var exported: [URL] = []
    public var failures: [(name: String, reason: String)] = []

    public init() {}
}
