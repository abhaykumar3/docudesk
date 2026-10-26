import Foundation

extension WorkspaceStore {
    /// Creates one document per recipient from a source document: same items, text and settings,
    /// new number, the recipient's details, and any extra CSV columns as `{{field.x}}` values.
    /// Failures are collected rather than stopping the batch.
    public func bulkGenerate(from sourceID: UUID, recipients: [BulkRecipient], options: BulkOptions,
                             progress: ((Int, Int) -> Void)? = nil) throws -> BulkResult {
        let source = try loadDocument(id: sourceID)
        var result = BulkResult()
        for (index, recipient) in recipients.enumerated() {
            progress?(index, recipients.count)
            let name = recipient.party.name.isEmpty ? "Row \(index + 1)" : recipient.party.name
            do {
                var document = try duplicate(sourceID)
                var customerID = recipient.customerID
                if customerID == nil, options.saveNewClients, !recipient.party.isEmpty {
                    let customer = Customer(party: recipient.party)
                    try saveCustomer(customer)
                    customerID = customer.id
                }
                document.customerID = customerID
                document.customer = recipient.party
                document.issueDate = options.issueDate
                if let profile = try profile(id: document.profileID) {
                    document.dueDate = document.defaultDueDays(profile).map { options.issueDate.adding(days: $0) }
                }
                for (key, value) in recipient.fields { document.customFields[key] = value }
                document.links = [DocumentLink(kind: .duplicatedFrom, documentID: source.id, number: source.number)]
                document = try save(document)
                if options.issue { document = try issue(document) }
                if let folder = options.exportFolder {
                    let url = Self.uniqueURL(in: folder, name: "\(document.number) \(Self.safeFileName(name)).pdf")
                    try renderPDF(document).data.write(to: url, options: .atomic)
                    document.exports.append(ExportRecord(path: url.path, exportedAt: Date(), revision: document.revision))
                    document = try save(document)
                    result.exported.append(url)
                }
                result.created.append(document)
            } catch {
                result.failures.append((name, error.localizedDescription))
            }
        }
        progress?(recipients.count, recipients.count)
        return result
    }

    static func safeFileName(_ name: String) -> String {
        String(name.map { "/:\\".contains($0) ? "-" : $0 }.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// Imports clients from CSV. Rows whose name matches an existing client are skipped.
    public func importCustomers(csv: String) throws -> (added: Int, skipped: [String]) {
        let existing = Set(try customers(includeArchived: true).map { $0.name.lowercased() })
        var added = 0
        var skipped: [String] = []
        var seen = existing
        try database.transaction {
            for record in CSV.records(csv).rows {
                let recipient = BulkRecipient(record: record)
                let name = recipient.party.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                guard seen.insert(name.lowercased()).inserted else {
                    skipped.append(name)
                    continue
                }
                var customer = Customer(party: recipient.party)
                customer.notes = record["notes"] ?? ""
                if let currency = record["currency"], !currency.isEmpty { customer.defaultCurrency = currency.uppercased() }
                if let terms = record["payment_terms"].flatMap(Int.init) { customer.paymentTermsDays = terms }
                try saveCustomer(customer)
                added += 1
            }
        }
        return (added, skipped)
    }

    /// Imports products and services from CSV (name, description, sku, hsn, unit, price, tax).
    public func importProducts(csv: String) throws -> (added: Int, skipped: [String]) {
        var seen = Set(try products(includeArchived: true).map { $0.name.lowercased() })
        var added = 0
        var skipped: [String] = []
        try database.transaction {
            for record in CSV.records(csv).rows {
                let name = (record["name"] ?? record["item"] ?? record["product"] ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                guard seen.insert(name.lowercased()).inserted else {
                    skipped.append(name)
                    continue
                }
                var product = ProductService(name: name)
                product.details = record["description"] ?? record["details"] ?? ""
                product.sku = record["sku"] ?? record["code"] ?? ""
                product.hsnSac = record["hsn"] ?? record["sac"] ?? record["hsn_sac"] ?? ""
                product.unit = (record["unit"]).flatMap { $0.isEmpty ? nil : $0 } ?? "nos"
                product.price = (record["price"] ?? record["rate"]).flatMap(Decimal.parse) ?? 0
                product.taxRate = (record["tax"] ?? record["tax_rate"] ?? record["gst"]).flatMap(Decimal.parse) ?? 0
                product.isService = ["service", "yes", "true", "1"].contains((record["service"] ?? record["type"] ?? "").lowercased())
                try saveProduct(product)
                added += 1
            }
        }
        return (added, skipped)
    }
}
