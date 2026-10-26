import Foundation

extension Dictionary: DefaultInitializable {}

/// How a custom document type is laid out.
public enum CustomLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case items
    case text
    case itemsAndText

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .items: "Items table (like an invoice)"
        case .text: "Written content (like a letter)"
        case .itemsAndText: "Written content with an items table"
        }
    }
}

public enum CustomFieldType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case multiline
    case number
    case date
    case choice
    case checkbox

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: "Text"
        case .multiline: "Long text"
        case .number: "Number"
        case .date: "Date"
        case .choice: "Choice"
        case .checkbox: "Yes / No"
        }
    }
}

/// Where a custom field appears on the printed document.
public enum CustomFieldPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Beside the number and date.
    case meta
    /// A "Details" section below the parties.
    case details
    /// Kept on the record only.
    case hidden

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .meta: "With number & date"
        case .details: "Details section"
        case .hidden: "Not printed"
        }
    }
}

public struct CustomFieldDefinition: Codable, Identifiable, Hashable, Sendable {
    /// Stable key used for stored values and `{{field.key}}` merge fields.
    public var id: String
    public var label: String
    public var type: CustomFieldType = .text
    public var placement: CustomFieldPlacement = .details
    public var choices: [String] = []
    public var required: Bool = false
    public var defaultValue: String = ""

    public init(id: String, label: String, type: CustomFieldType = .text, placement: CustomFieldPlacement = .details) {
        self.id = id
        self.label = label
        self.type = type
        self.placement = placement
    }

    /// `"Site Address"` → `"site_address"`.
    public static func key(for label: String) -> String {
        let slug = label.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let collapsed = String(slug).split(separator: "_").joined(separator: "_")
        return collapsed.isEmpty ? "field" : collapsed
    }

    /// Value as printed, e.g. dates in display form and checkboxes as Yes/No.
    public func display(_ raw: String) -> String {
        switch type {
        case .date: CalendarDate(iso: raw)?.display ?? raw
        case .checkbox: raw == "true" ? "Yes" : "No"
        default: raw
        }
    }
}

/// A user-defined document type (e.g. "Work Order", "Site Visit Report") with its own name,
/// numbering prefix, layout, labels and fields. Documents keep a snapshot of the type they were
/// made with, so editing the type never changes issued documents.
public struct CustomDocumentType: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var pluralName: String
    public var prefix: String
    public var layout: CustomLayout = .items
    public var printedTitle: String
    public var partyLabel: String = "Bill To"
    public var numberLabel: String = "No."
    /// Label for a second date; nil hides it.
    public var dueDateLabel: String?
    public var dueDays: Int = 15
    public var showsPricing: Bool = true
    public var fields: [CustomFieldDefinition] = []
    public var statuses: [DocumentStatus] = [.draft, .issued, .sent, .accepted, .cancelled]
    public var starterText: String = ""
    public var archived: Bool = false
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, prefix: String? = nil, layout: CustomLayout = .items, now: Date = Date()) {
        self.id = id
        self.name = name
        pluralName = name.hasSuffix("s") ? name : name + "s"
        self.prefix = prefix ?? String(name.split(separator: " ").compactMap(\.first).prefix(3)).uppercased()
        self.layout = layout
        printedTitle = name
        numberLabel = "\(name) No."
        createdAt = now
        updatedAt = now
    }

    public var key: String { "custom.\(id.uuidString)" }

    public var folderName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -&()"))
        let cleaned = String(pluralName.unicodeScalars.filter { allowed.contains($0) }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Custom Documents" : cleaned
    }
}

// MARK: - Type-aware properties

/// Properties that depend on the document type. Built-in documents defer to `DocumentKind`;
/// custom documents use their type snapshot.
extension DocumentRecord {
    public var typeName: String { customType?.name ?? kind.displayName }
    public var typePluralName: String { customType?.pluralName ?? kind.pluralName }
    public var typeFolderName: String { customType?.folderName ?? kind.folderName }
    public var numberingKey: String { customType?.key ?? kind.rawValue }
    public var defaultPrefix: String { customType?.prefix ?? kind.defaultPrefix }

    public var usesLineItems: Bool { customType.map { $0.layout != .text } ?? kind.usesLineItems }
    public var usesBody: Bool { customType.map { $0.layout != .items } ?? kind.usesBody }
    public var showsPricing: Bool { customType.map { $0.showsPricing && $0.layout != .text } ?? kind.showsPricing }
    public var printedTitle: String { customType.map { $0.layout == .items ? $0.printedTitle : "" } ?? kind.documentTitle }
    public var numberLabel: String { customType?.numberLabel ?? kind.numberLabel }
    public var partyLabel: String { customType?.partyLabel ?? kind.partyLabel }
    public var dueDateLabel: String? { customType != nil ? customType?.dueDateLabel : kind.dueDateLabel }
    public var statuses: [DocumentStatus] { customType?.statuses ?? kind.statuses }

    public func defaultDueDays(_ profile: CompanyProfile) -> Int? {
        if let customType { return customType.dueDateLabel == nil ? nil : customType.dueDays }
        return kind.defaultDueDays(profile)
    }

    /// Custom fields to print in a given place, as (label, value) pairs; empty values are skipped.
    public func customFieldRows(_ placement: CustomFieldPlacement) -> [(String, String)] {
        (customType?.fields ?? []).filter { $0.placement == placement }.compactMap { field in
            let raw = customFields[field.id] ?? ""
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty || field.type == .checkbox else { return nil }
            return (field.label, field.display(raw))
        }
    }

    /// Required custom fields that are still empty.
    public var missingRequiredFields: [String] {
        (customType?.fields ?? []).filter { $0.required && (customFields[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.map(\.label)
    }
}
