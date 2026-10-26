import Foundation

public struct LineItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var productID: UUID?
    public var name: String = ""
    public var details: String = ""
    public var hsnSac: String = ""
    @DecimalString public var quantity: Decimal = 1
    public var unit: String = ""
    @DecimalString public var unitPrice: Decimal = 0
    public var discountKind: DiscountKind = .percent
    @DecimalString public var discountValue: Decimal = 0
    @DecimalString public var taxRate: Decimal = 0

    public init(name: String = "", quantity: Decimal = 1, unitPrice: Decimal = 0, taxRate: Decimal = 0) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.taxRate = taxRate
    }

    public init(product: ProductService, fallbackTaxRate: Decimal) {
        self.init(name: product.name, quantity: 1, unitPrice: product.price, taxRate: product.taxRate > 0 ? product.taxRate : fallbackTaxRate)
        productID = product.id
        details = product.details
        hsnSac = product.hsnSac
        unit = product.unit
    }
}

public struct ReceiptDetails: Codable, Hashable, Sendable {
    @DecimalString public var amountReceived: Decimal = 0
    public var method: PaymentMethod = .bankTransfer
    public var transactionReference: String = ""
    public var againstDocumentID: UUID?
    public var againstDocumentNumber: String = ""
    public var purpose: String = ""

    public init() {}
}

public struct PaymentRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var date: CalendarDate
    @DecimalString public var amount: Decimal = 0
    public var method: PaymentMethod = .bankTransfer
    public var reference: String = ""
    public var note: String = ""
    /// Receipt document generated for this payment, if any.
    public var receiptID: UUID?
    public var receiptNumber: String?

    public init(date: CalendarDate = .today, amount: Decimal, method: PaymentMethod = .bankTransfer, reference: String = "", note: String = "") {
        self.date = date
        self.amount = amount
        self.method = method
        self.reference = reference
        self.note = note
    }
}

/// Word-processor content of proposals, agreements, letters and reports.
/// `rtfd` is flattened RTFD (keeps formatting, tables and images); `plainText` keeps the
/// record searchable and readable without AppKit.
public struct RichTextBody: Codable, Hashable, Sendable, DefaultInitializable {
    public var rtfd: Data = Data()
    public var plainText: String = ""

    public init() {}

    public init(rtfd: Data, plainText: String) {
        self.rtfd = rtfd
        self.plainText = plainText
    }

    public var isEmpty: Bool { rtfd.isEmpty && plainText.isEmpty }
}

public enum LinkKind: String, Codable, Sendable {
    case convertedFrom
    case convertedTo
    case duplicatedFrom
    case paymentFor
    case paymentReceipt

    public var displayName: String {
        switch self {
        case .convertedFrom: "Converted from"
        case .convertedTo: "Converted to"
        case .duplicatedFrom: "Duplicated from"
        case .paymentFor: "Payment for"
        case .paymentReceipt: "Receipt"
        }
    }
}

public struct DocumentLink: Codable, Hashable, Sendable {
    public var kind: LinkKind
    public var documentID: UUID
    public var number: String

    public init(kind: LinkKind, documentID: UUID, number: String) {
        self.kind = kind
        self.documentID = documentID
        self.number = number
    }
}

public struct ExportRecord: Codable, Hashable, Sendable {
    public var path: String
    public var exportedAt: Date
    public var revision: Int
}

public struct DocumentRecord: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int = DocumentRecord.currentSchemaVersion
    public var id: UUID
    public var kind: DocumentKind
    public var number: String
    public var title: String = ""
    public var status: DocumentStatus = .draft
    public var revision: Int = 1

    public var profileID: UUID
    /// Seller details at the time of saving. Issued documents keep this even if the profile changes.
    public var company: CompanyProfile
    public var customerID: UUID?
    public var customer = PartyDetails()

    public var issueDate: CalendarDate
    public var dueDate: CalendarDate?
    public var reference: String = ""
    public var placeOfSupply: String = ""

    public var currency: String
    public var taxMode: TaxMode = .exclusive
    public var taxSplit: TaxSplit = .cgstSgst
    public var taxLabel: String = "Tax"
    public var items: [LineItem] = []
    public var documentDiscountKind: DiscountKind = .amount
    @DecimalString public var documentDiscountValue: Decimal = 0
    @DecimalString public var shipping: Decimal = 0
    @DecimalString public var adjustment: Decimal = 0
    public var adjustmentLabel: String = "Adjustment"
    public var roundOffTotal: Bool = false
    @DecimalString public var advancePaid: Decimal = 0
    /// Payments recorded against an issued invoice. Not part of the locked content.
    @Defaulted public var payments: [PaymentRecord] = []
    public var receipt: ReceiptDetails?
    @Defaulted public var body = RichTextBody()
    /// Snapshot of the user-defined type for `.custom` documents.
    public var customType: CustomDocumentType?
    /// Values of the type's custom fields, keyed by field ID.
    @Defaulted public var customFields: [String: String] = [:]

    public var notes: String = ""
    public var terms: String = ""
    public var paymentDetails: String = ""

    public var templateID: String
    public var templateVersion: Int
    /// The exact theme used when the document was issued, so later template edits never change it.
    public var templateSnapshot: TemplateTheme?
    public var pageSize: PageSize = .a4
    public var orientation: PageOrientation = .portrait

    @Defaulted public var tags: [String] = []
    @Defaulted public var pinned: Bool = false
    @Defaulted public var archived: Bool = false
    public var links: [DocumentLink] = []
    public var exports: [ExportRecord] = []
    public var createdAt: Date
    public var updatedAt: Date
    public var issuedAt: Date?

    /// Calculated by `DocumentCalculator` on every save and stored for portability.
    public var totals = DocumentTotals()

    public init(id: UUID = UUID(), kind: DocumentKind, number: String, company: CompanyProfile, template: TemplateDefinition, issueDate: CalendarDate = .today, now: Date = Date()) {
        self.id = id
        self.kind = kind
        self.number = number
        self.profileID = company.id
        self.company = company
        self.issueDate = issueDate
        self.currency = company.defaultCurrency
        self.taxSplit = company.defaultTaxSplit
        self.taxMode = company.defaultTaxMode
        self.templateID = template.id
        self.templateVersion = template.version
        self.pageSize = company.defaultPageSize
        self.createdAt = now
        self.updatedAt = now
        self.notes = company.defaultNotes
        self.terms = company.defaultTerms
        self.paymentDetails = company.bankDetails
        dueDate = defaultDueDays(company).map { issueDate.adding(days: $0) }
        if kind == .receipt {
            receipt = ReceiptDetails()
            notes = ""
            terms = ""
            paymentDetails = ""
        } else if kind == .purchaseOrder || kind == .deliveryChallan || kind == .creditNote {
            paymentDetails = ""
        }
    }

    public var displayTitle: String {
        let customerName = customer.name.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        return customerName.isEmpty ? typeName : "\(typeName) for \(customerName)"
    }

    public var amountPaid: Decimal {
        payments.reduce(Decimal(0)) { $0 + $1.amount }
    }

    public var isOverdue: Bool {
        guard kind == .invoice, status.isOutstanding, let dueDate else { return false }
        return dueDate < .today && totals.balanceDue > 0
    }

    /// Text indexed for full-text search.
    public var searchBody: String {
        var parts = items.flatMap { [$0.name, $0.details, $0.hsnSac] }
        parts += [notes, reference, customer.contactPerson, customer.email, customer.taxID, body.plainText]
        parts += tags
        parts += customFields.values
        if let receipt { parts += [receipt.againstDocumentNumber, receipt.transactionReference, receipt.purpose] }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
