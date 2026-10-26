import Foundation

public struct NumberingRule: Codable, Hashable, Sendable {
    public var prefix: String
    public var includeYear: Bool = true
    public var padding: Int = 4
    public var nextNumber: Int = 1
    /// Restart the sequence at 1 when the issue year changes.
    public var resetYearly: Bool = true
    public var lastYear: Int?

    public init(prefix: String, includeYear: Bool = true, padding: Int = 4, nextNumber: Int = 1, resetYearly: Bool = true, lastYear: Int? = nil) {
        self.prefix = prefix
        self.includeYear = includeYear
        self.padding = padding
        self.nextNumber = nextNumber
        self.resetYearly = resetYearly
        self.lastYear = lastYear
    }

    public func format(_ number: Int, year: Int) -> String {
        let digits = String(number)
        let padded = String(repeating: "0", count: max(0, padding - digits.count)) + digits
        let parts = [prefix.trimmingCharacters(in: .whitespaces), includeYear ? String(year) : nil, padded]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "-")
    }

    /// Number that the next allocation in `year` will start from.
    public func candidate(for year: Int) -> Int {
        if resetYearly, includeYear, let lastYear, lastYear != year { return 1 }
        return max(1, nextNumber)
    }
}

public struct CompanyProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var legalName: String = ""
    public var address = Address()
    public var email: String = ""
    public var phone: String = ""
    public var website: String = ""
    public var taxIDLabel: String = "GSTIN"
    public var taxID: String = ""
    /// Path relative to the workspace root, e.g. `Assets/logo-<id>.png`.
    public var logoPath: String?
    public var signatoryName: String = ""
    public var bankDetails: String = ""
    /// UPI ID for payment QR codes, e.g. `business@okhdfcbank`.
    @Defaulted public var upiID: String = ""
    public var defaultCurrency: String = "INR"
    @DecimalString public var defaultTaxRate: Decimal = 18
    public var defaultTaxSplit: TaxSplit = .cgstSgst
    public var defaultTaxMode: TaxMode = .exclusive
    public var defaultPaymentTermsDays: Int = 15
    public var defaultQuoteValidityDays: Int = 30
    public var defaultNotes: String = "Thank you for your business."
    public var defaultTerms: String = ""
    public var defaultTemplateStyle: TemplateStyle = .modern
    public var defaultPageSize: PageSize = .a4
    public var numbering: [String: NumberingRule] = [:]
    /// Folder under `Documents/` for this profile's files; empty for the workspace's first profile.
    @Defaulted public var folderName: String = ""
    /// Default custom template (`custom.<id>`), overriding `defaultTemplateStyle` when set.
    public var defaultTemplateID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, now: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = now
        self.updatedAt = now
        for kind in DocumentKind.builtIn {
            numbering[kind.rawValue] = NumberingRule(prefix: kind.defaultPrefix)
        }
    }

    public func numberingRule(for kind: DocumentKind) -> NumberingRule {
        numbering[kind.rawValue] ?? NumberingRule(prefix: kind.defaultPrefix)
    }

    /// Rule for a built-in kind (`kind.rawValue`) or a custom type (`custom.<id>`).
    public func numberingRule(forKey key: String, defaultPrefix: String) -> NumberingRule {
        numbering[key] ?? NumberingRule(prefix: defaultPrefix)
    }

    public var displayLegalName: String { legalName.isEmpty ? name : legalName }
}

/// Customer details as they appear on a document; frozen into the document when saved.
public struct PartyDetails: Codable, Hashable, Sendable {
    public var name: String = ""
    public var contactPerson: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var billingAddress = Address()
    public var shippingAddress = Address()
    public var taxID: String = ""

    public init(name: String = "") {
        self.name = name
    }

    public var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct Customer: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isCompany: Bool = true
    public var contactPerson: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var billingAddress = Address()
    public var shippingAddress = Address()
    public var shippingSameAsBilling: Bool = true
    public var taxID: String = ""
    public var defaultCurrency: String = ""
    public var paymentTermsDays: Int?
    public var notes: String = ""
    public var archived: Bool = false
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, now: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = now
        self.updatedAt = now
    }

    public var party: PartyDetails {
        var party = PartyDetails(name: name)
        party.contactPerson = contactPerson
        party.email = email
        party.phone = phone
        party.billingAddress = billingAddress
        party.shippingAddress = shippingSameAsBilling ? Address() : shippingAddress
        party.taxID = taxID
        return party
    }

    public init(party: PartyDetails, now: Date = Date()) {
        self.init(name: party.name, now: now)
        contactPerson = party.contactPerson
        email = party.email
        phone = party.phone
        billingAddress = party.billingAddress
        shippingAddress = party.shippingAddress
        shippingSameAsBilling = party.shippingAddress.isEmpty
        taxID = party.taxID
    }
}

public struct ProductService: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var details: String = ""
    public var sku: String = ""
    public var hsnSac: String = ""
    public var unit: String = "nos"
    @DecimalString public var price: Decimal = 0
    public var currency: String = ""
    @DecimalString public var taxRate: Decimal = 0
    public var isService: Bool = false
    public var archived: Bool = false
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, now: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = now
        self.updatedAt = now
    }
}
