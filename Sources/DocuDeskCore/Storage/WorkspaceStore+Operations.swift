import Foundation

public enum PaymentError: LocalizedError, Equatable {
    case notAnInvoice
    case notOutstanding(String)
    case invalidAmount
    case exceedsBalance(String)

    public var errorDescription: String? {
        switch self {
        case .notAnInvoice: "Payments can only be recorded against invoices."
        case let .notOutstanding(number): "\(number) isn’t awaiting payment. Issue it first, or it may already be paid or cancelled."
        case .invalidAmount: "Enter an amount greater than zero."
        case let .exceedsBalance(balance): "That’s more than the balance due (\(balance))."
        }
    }
}

public struct SavedFilter: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var query: DocumentQuery

    public init(id: UUID = UUID(), name: String, query: DocumentQuery) {
        self.id = id
        self.name = name
        self.query = query
    }
}

// MARK: - Payments

extension WorkspaceStore {
    /// Records a payment on an issued invoice, updates its status, and optionally issues a receipt.
    @discardableResult
    public func recordPayment(_ payment: PaymentRecord, toInvoice id: UUID, createReceipt: Bool) throws -> (invoice: DocumentRecord, receipt: DocumentRecord?) {
        var invoice = try loadDocument(id: id)
        guard invoice.kind.acceptsPayments else { throw PaymentError.notAnInvoice }
        guard invoice.status.isOutstanding else { throw PaymentError.notOutstanding(invoice.number) }
        var payment = payment
        payment.amount = payment.amount.rounded(2)
        guard payment.amount > 0 else { throw PaymentError.invalidAmount }
        let balance = DocumentCalculator.totals(for: invoice).balanceDue
        guard payment.amount <= balance else {
            throw PaymentError.exceedsBalance(MoneyFormatter.format(balance, currency: invoice.currency))
        }

        var receipt: DocumentRecord?
        if createReceipt {
            var draft = try newDocument(kind: .receipt, profileID: invoice.profileID)
            draft.customerID = invoice.customerID
            draft.customer = invoice.customer
            draft.currency = invoice.currency
            draft.issueDate = payment.date
            var details = ReceiptDetails()
            details.amountReceived = payment.amount
            details.method = payment.method
            details.transactionReference = payment.reference
            details.againstDocumentID = invoice.id
            details.againstDocumentNumber = invoice.number
            details.purpose = payment.note
            draft.receipt = details
            draft.links = [DocumentLink(kind: .paymentFor, documentID: invoice.id, number: invoice.number)]
            if CustomTemplate.id(from: invoice.templateID) != nil {
                draft.templateID = invoice.templateID
            } else if let style = TemplateLibrary.template(id: invoice.templateID)?.style {
                draft.templateID = TemplateLibrary.defaultTemplate(for: .receipt, style: style).id
            }
            receipt = try issue(try save(draft))
            payment.receiptID = receipt?.id
            payment.receiptNumber = receipt?.number
            invoice.links.append(DocumentLink(kind: .paymentReceipt, documentID: receipt!.id, number: receipt!.number))
        }

        invoice.payments.append(payment)
        let remaining = DocumentCalculator.totals(for: invoice).balanceDue
        invoice.status = remaining <= 0 ? .paid : .partiallyPaid
        let saved = try save(invoice)
        return (saved, receipt)
    }

    /// Removes a payment (e.g. entered by mistake). Its receipt, if any, is marked cancelled.
    @discardableResult
    public func deletePayment(_ paymentID: UUID, fromInvoice id: UUID) throws -> DocumentRecord {
        var invoice = try loadDocument(id: id)
        guard let payment = invoice.payments.first(where: { $0.id == paymentID }) else { throw WorkspaceError.recordNotFound }
        invoice.payments.removeAll { $0.id == paymentID }
        if invoice.status != .cancelled {
            invoice.status = invoice.payments.isEmpty ? .issued : .partiallyPaid
        }
        let saved = try save(invoice)
        if let receiptID = payment.receiptID, (try? loadDocument(id: receiptID)) != nil {
            try setStatus(.cancelled, for: receiptID)
        }
        return saved
    }
}

// MARK: - Organisation and bulk operations

extension WorkspaceStore {
    private func update(_ ids: [UUID], _ change: (inout DocumentRecord) -> Void) throws {
        for id in ids {
            var document = try loadDocument(id: id)
            change(&document)
            try save(document)
        }
    }

    public func setTags(_ tags: [String], for ids: [UUID]) throws {
        try update(ids) { $0.tags = tags }
    }

    public func addTag(_ tag: String, to ids: [UUID]) throws {
        try update(ids) { $0.tags.append(tag) }
    }

    public func removeTag(_ tag: String, from ids: [UUID]) throws {
        try update(ids) { document in document.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } }
    }

    public func setArchived(_ archived: Bool, for ids: [UUID]) throws {
        try update(ids) { $0.archived = archived }
    }

    public func setPinned(_ pinned: Bool, for ids: [UUID]) throws {
        try update(ids) { $0.pinned = pinned }
    }

    public func allTags() throws -> [String] {
        let rows = try database.query("SELECT DISTINCT tags FROM documents WHERE tags != ''")
        var seen = Set<String>()
        return rows.flatMap { Self.decodeTags($0.string("tags") ?? "") }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Writes PDFs for the given documents into `directory`; also records each export.
    @discardableResult
    public func exportPDFs(_ ids: [UUID], to directory: URL) throws -> [URL] {
        var urls: [URL] = []
        for id in ids {
            var document = try loadDocument(id: id)
            let url = Self.uniqueURL(in: directory, name: pdfFileName(for: document))
            do {
                try renderPDF(document).data.write(to: url, options: .atomic)
            } catch {
                throw WorkspaceError.notWritable(url.path)
            }
            document.exports.append(ExportRecord(path: url.path, exportedAt: Date(), revision: document.revision))
            try save(document)
            urls.append(url)
        }
        return urls
    }

    /// Copies the selected records (JSON, PDFs, revisions) into a new folder with an index CSV.
    @discardableResult
    public func exportRecords(_ ids: [UUID], to directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let root = Self.uniqueURL(in: directory, name: "DocuDesk Records \(formatter.string(from: Date()))")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var lines = ["Number,Type,Client,Date,Currency,Total,Status,Folder"]
        for id in ids {
            let document = try loadDocument(id: id)
            let source = try documentFolder(for: id)
            let relative = "\(document.typeFolderName)/\(document.number)"
            let target = root.appendingPathComponent(relative)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
            lines.append([document.number, document.typeName, document.customer.name, document.issueDate.iso, document.currency,
                          document.totals.grandTotal.plainString, document.status.displayName, relative].map(Self.csvField).joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: root.appendingPathComponent("index.csv"), atomically: true, encoding: .utf8)
        return root
    }

    /// Deletes drafts only; returns the numbers that were skipped because they were issued.
    public func deleteDrafts(_ ids: [UUID], moveToTrash: Bool = true) throws -> [String] {
        var skipped: [String] = []
        for id in ids {
            let document = try loadDocument(id: id)
            if document.status == .draft, document.revision == 1 {
                try deleteDraft(id: id, moveToTrash: moveToTrash)
            } else {
                skipped.append(document.number)
            }
        }
        return skipped
    }

    /// Same type, client and total within 30 days: likely entered twice.
    public func possibleDuplicates(of document: DocumentRecord) throws -> [DocumentSummary] {
        let total = DocumentCalculator.totals(for: document).grandTotal
        guard total > 0, !document.customer.name.isEmpty, document.showsPricing else { return [] }
        let rows = try database.query("""
        SELECT * FROM documents WHERE id != ? AND type_key = ? AND customer_name = ? COLLATE NOCASE AND total_minor = ?
        AND issue_date BETWEEN ? AND ? AND status != 'cancelled'
        """, [
            .text(document.id.uuidString), .text(document.numberingKey), .text(document.customer.name), .int(total.minorUnits),
            .text(document.issueDate.adding(days: -30).iso), .text(document.issueDate.adding(days: 30).iso),
        ])
        return rows.compactMap(Self.summary(from:))
    }

    static func csvField(_ value: String) -> String {
        value.contains(where: { ",\"\n".contains($0) }) ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
    }

    static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = directory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return url
    }
}

// MARK: - Saved filters and recent documents

extension WorkspaceStore {
    public func savedFilters() -> [SavedFilter] {
        guard let data = setting(.savedFilters)?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SavedFilter].self, from: data)) ?? []
    }

    public func setSavedFilters(_ filters: [SavedFilter]) throws {
        try setSetting(.savedFilters, String(decoding: try JSONEncoder().encode(filters), as: UTF8.self))
    }

    public func noteOpened(_ id: UUID) {
        var ids = recentDocumentIDs().filter { $0 != id }
        ids.insert(id, at: 0)
        try? setSetting(.recentDocuments, ids.prefix(12).map(\.uuidString).joined(separator: ","))
    }

    public func recentDocumentIDs() -> [UUID] {
        (setting(.recentDocuments) ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    public func recentlyOpened() -> [DocumentSummary] {
        let ids = recentDocumentIDs()
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = (try? database.query("SELECT * FROM documents WHERE id IN (\(placeholders))", ids.map { .text($0.uuidString) })) ?? []
        let byID = Dictionary(uniqueKeysWithValues: rows.compactMap(Self.summary(from:)).map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
}
