import Foundation

public enum CustomTypeError: LocalizedError {
    case nameRequired
    case duplicateFieldKeys([String])
    case missingRequiredFields([String])

    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Give the document type a name."
        case let .duplicateFieldKeys(keys): "Each field needs a different label (repeated: \(keys.joined(separator: ", ")))."
        case let .missingRequiredFields(labels): "Fill in the required fields before issuing: \(labels.joined(separator: ", "))."
        }
    }
}

extension WorkspaceStore {
    public func customTypes(includeArchived: Bool = false) throws -> [CustomDocumentType] {
        try database.query("SELECT json FROM custom_types ORDER BY name COLLATE NOCASE").compactMap { row in
            row.string("json").flatMap { $0.data(using: .utf8) }.flatMap { try? DocuDeskJSON.decoder.decode(CustomDocumentType.self, from: $0) }
        }
        .filter { includeArchived || !$0.archived }
    }

    public func customType(id: UUID) throws -> CustomDocumentType? {
        try database.query("SELECT json FROM custom_types WHERE id = ?", [.text(id.uuidString)]).first
            .flatMap { $0.string("json")?.data(using: .utf8) }
            .flatMap { try? DocuDeskJSON.decoder.decode(CustomDocumentType.self, from: $0) }
    }

    /// Saves a type. Issued documents keep their snapshot; drafts pick up the change on next save.
    @discardableResult
    public func saveCustomType(_ type: CustomDocumentType) throws -> CustomDocumentType {
        var type = type
        type.name = type.name.trimmingCharacters(in: .whitespaces)
        guard !type.name.isEmpty else { throw CustomTypeError.nameRequired }
        if type.pluralName.trimmingCharacters(in: .whitespaces).isEmpty { type.pluralName = type.name + "s" }
        if type.prefix.trimmingCharacters(in: .whitespaces).isEmpty { type.prefix = "DOC" }
        type.prefix = String(type.prefix.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(8)).uppercased()
        for index in type.fields.indices where type.fields[index].id.isEmpty {
            type.fields[index].id = CustomFieldDefinition.key(for: type.fields[index].label)
        }
        let keys = type.fields.map(\.id)
        let repeated = Set(keys.filter { key in keys.filter { $0 == key }.count > 1 })
        guard repeated.isEmpty else { throw CustomTypeError.duplicateFieldKeys(repeated.sorted()) }
        if !type.statuses.contains(.draft) { type.statuses.insert(.draft, at: 0) }
        type.updatedAt = Date()
        let json = String(decoding: try DocuDeskJSON.encoder.encode(type), as: UTF8.self)
        try database.run(
            "INSERT INTO custom_types(id, name, json, updated_at) VALUES(?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, json = excluded.json, updated_at = excluded.updated_at",
            [.text(type.id.uuidString), .text(type.name), .text(json), .text(Self.timestamp.string(from: type.updatedAt))]
        )
        return type
    }

    /// Types with documents are archived (hidden from menus) rather than deleted.
    public func deleteCustomType(id: UUID) throws {
        var query = DocumentQuery()
        query.customTypeID = id
        query.archive = .all
        if try !search(query).isEmpty, var type = try customType(id: id) {
            type.archived = true
            try saveCustomType(type)
        } else {
            try database.run("DELETE FROM custom_types WHERE id = ?", [.text(id.uuidString)])
        }
    }

    public func newDocument(customType: CustomDocumentType, profileID: UUID? = nil, templateID: String? = nil, customer: Customer? = nil) throws -> DocumentRecord {
        guard let profile = try profileID.flatMap({ try self.profile(id: $0) }) ?? defaultProfile() else {
            throw WorkspaceError.recordNotFound
        }
        let template = try templateDefinition(id: templateID ?? profile.defaultTemplateID, kind: .custom)
            ?? TemplateLibrary.defaultTemplate(for: .custom, style: profile.defaultTemplateStyle)
        let today = CalendarDate.today
        let number = try allocateNumber(key: customType.key, defaultPrefix: customType.prefix, kind: .custom, profileID: profile.id, year: today.year)
        var document = DocumentRecord(kind: .custom, number: number, company: profile, template: template, issueDate: today)
        document.customType = customType
        document.dueDate = document.defaultDueDays(profile).map { today.adding(days: $0) }
        for field in customType.fields where !field.defaultValue.isEmpty {
            document.customFields[field.id] = field.defaultValue
        }
        if let customer { apply(customer: customer, to: &document) }
        if document.usesBody {
            let markup = customType.starterText.isEmpty ? "# \(customType.printedTitle)" : customType.starterText
            document.body = RichTextBody(attributed: RichTextBuilder.build(markup, theme: template.theme))
            document.notes = ""
            document.terms = ""
        }
        if !customType.showsPricing { document.paymentDetails = "" }
        document.items = document.usesLineItems && !document.usesBody
            ? [LineItem(name: "", quantity: 1, unitPrice: 0, taxRate: customType.showsPricing ? profile.defaultTaxRate : 0)]
            : []
        if !customType.showsPricing { document.taxSplit = .none }
        return try save(document)
    }
}
