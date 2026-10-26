import Foundation

public struct DiffEntry: Identifiable, Hashable, Sendable {
    public enum Change: String, Sendable {
        case added
        case removed
        case changed
    }

    public let id = UUID()
    public let section: String
    public let field: String
    public let old: String
    public let new: String
    public let change: Change
}

/// Field-by-field comparison of two versions of a document, for the revision history view.
public enum DocumentComparer {
    public static func compare(_ old: DocumentRecord, _ new: DocumentRecord) -> [DiffEntry] {
        var entries: [DiffEntry] = []
        func check(_ section: String, _ field: String, _ a: String, _ b: String) {
            guard a != b else { return }
            let change: DiffEntry.Change = a.isEmpty ? .added : b.isEmpty ? .removed : .changed
            entries.append(DiffEntry(section: section, field: field, old: a, new: b, change: change))
        }
        func money(_ value: Decimal, _ currency: String) -> String { MoneyFormatter.format(value, currency: currency) }

        check("Details", "Number", old.number, new.number)
        check("Details", "Title", old.title, new.title)
        check("Details", "Status", old.status.displayName, new.status.displayName)
        check("Details", "Date", old.issueDate.display, new.issueDate.display)
        check("Details", new.dueDateLabel ?? "Due date", old.dueDate?.display ?? "", new.dueDate?.display ?? "")
        check("Details", "Reference", old.reference, new.reference)
        check("Details", "Place of supply", old.placeOfSupply, new.placeOfSupply)
        check("Details", "Currency", old.currency, new.currency)
        check("Details", "Template", old.templateID, new.templateID)

        check("Client", "Name", old.customer.name, new.customer.name)
        check("Client", "Contact", old.customer.contactPerson, new.customer.contactPerson)
        check("Client", "Email", old.customer.email, new.customer.email)
        check("Client", "Address", old.customer.billingAddress.formatted, new.customer.billingAddress.formatted)
        check("Client", "Tax ID", old.customer.taxID, new.customer.taxID)
        check("Company", "Name", old.company.displayLegalName, new.company.displayLegalName)
        check("Company", "Tax ID", old.company.taxID, new.company.taxID)

        let fieldLabels = Dictionary((new.customType?.fields ?? old.customType?.fields ?? []).map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
        for key in Set(old.customFields.keys).union(new.customFields.keys).sorted() {
            check("Fields", fieldLabels[key] ?? key, old.customFields[key] ?? "", new.customFields[key] ?? "")
        }

        // Line items are matched by ID so edits show as changes rather than remove + add.
        let oldItems = Dictionary(old.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (index, item) in new.items.enumerated() {
            let label = "Item \(index + 1)"
            guard let before = oldItems[item.id] else {
                entries.append(DiffEntry(section: "Items", field: label, old: "", new: describe(item, new.currency), change: .added))
                continue
            }
            if before != item {
                entries.append(DiffEntry(section: "Items", field: label, old: describe(before, old.currency), new: describe(item, new.currency), change: .changed))
            }
        }
        let newIDs = Set(new.items.map(\.id))
        for item in old.items where !newIDs.contains(item.id) {
            entries.append(DiffEntry(section: "Items", field: item.name.isEmpty ? "Item" : item.name, old: describe(item, old.currency), new: "", change: .removed))
        }

        let oldTotals = DocumentCalculator.totals(for: old)
        let newTotals = DocumentCalculator.totals(for: new)
        check("Totals", "Discount", money(oldTotals.documentDiscount, old.currency), money(newTotals.documentDiscount, new.currency))
        check("Totals", "Tax", money(oldTotals.taxTotal, old.currency), money(newTotals.taxTotal, new.currency))
        check("Totals", "Total", money(oldTotals.grandTotal, old.currency), money(newTotals.grandTotal, new.currency))

        check("Text", "Notes", old.notes, new.notes)
        check("Text", "Terms", old.terms, new.terms)
        check("Text", "Payment details", old.paymentDetails, new.paymentDetails)
        entries += bodyDiff(old.body.plainText, new.body.plainText)
        return entries
    }

    static func describe(_ item: LineItem, _ currency: String) -> String {
        var text = "\(item.name.isEmpty ? "Item" : item.name) · \(MoneyFormatter.quantity(item.quantity)) × \(MoneyFormatter.format(item.unitPrice, currency: currency))"
        if item.discountValue > 0 { text += " · disc \(MoneyFormatter.quantity(item.discountValue))\(item.discountKind == .percent ? "%" : "")" }
        if item.taxRate > 0 { text += " · tax \(MoneyFormatter.quantity(item.taxRate))%" }
        return text
    }

    /// Paragraph-level diff of body text using a longest-common-subsequence alignment.
    static func bodyDiff(_ old: String, _ new: String) -> [DiffEntry] {
        guard old != new else { return [] }
        let a = paragraphs(old)
        let b = paragraphs(new)
        guard a.count * b.count <= 4_000_000 else {
            return [DiffEntry(section: "Content", field: "Body", old: "\(a.count) paragraphs", new: "\(b.count) paragraphs", change: .changed)]
        }
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var entries: [DiffEntry] = []
        var i = 0
        var j = 0
        var pendingRemoved: [String] = []
        func flush(added: String?) {
            if let removed = pendingRemoved.first, let added {
                entries.append(DiffEntry(section: "Content", field: "Paragraph", old: removed, new: added, change: .changed))
                pendingRemoved.removeFirst()
            } else if let added {
                entries.append(DiffEntry(section: "Content", field: "Paragraph", old: "", new: added, change: .added))
            }
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                for removed in pendingRemoved {
                    entries.append(DiffEntry(section: "Content", field: "Paragraph", old: removed, new: "", change: .removed))
                }
                pendingRemoved = []
                i += 1
                j += 1
            } else if i < a.count, j == b.count || lcs[i + 1][j] >= lcs[i][j + 1] {
                // Removals go first so a following addition pairs with them as a change.
                pendingRemoved.append(a[i])
                i += 1
            } else {
                flush(added: b[j])
                j += 1
            }
        }
        for removed in pendingRemoved {
            entries.append(DiffEntry(section: "Content", field: "Paragraph", old: removed, new: "", change: .removed))
        }
        return entries
    }

    private static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{000C}"))) }
            .filter { !$0.isEmpty }
    }
}
