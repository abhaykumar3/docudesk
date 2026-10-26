import Foundation

public enum DocumentCategory: String, CaseIterable, Identifiable, Sendable {
    case sales
    case purchase
    case business
    case finance

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum DocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case invoice
    case quotation
    case estimate
    case proformaInvoice
    case purchaseOrder
    case creditNote
    case deliveryChallan
    case receipt
    case proposal
    case agreement
    case letter
    case report
    /// A user-defined type; the document's `customType` snapshot supplies its name and layout.
    case custom

    public var id: String { rawValue }

    /// Every kind except `.custom`, for menus and pickers.
    public static let builtIn: [DocumentKind] = allCases.filter { $0 != .custom }

    public var displayName: String {
        switch self {
        case .invoice: "Invoice"
        case .quotation: "Quotation"
        case .estimate: "Estimate"
        case .proformaInvoice: "Proforma Invoice"
        case .purchaseOrder: "Purchase Order"
        case .creditNote: "Credit Note"
        case .deliveryChallan: "Delivery Challan"
        case .receipt: "Payment Receipt"
        case .proposal: "Proposal"
        case .agreement: "Agreement"
        case .letter: "Letter"
        case .report: "Report"
        case .custom: "Custom Document"
        }
    }

    public var pluralName: String {
        switch self {
        case .invoice: "Invoices"
        case .quotation: "Quotations"
        case .estimate: "Estimates"
        case .proformaInvoice: "Proforma Invoices"
        case .purchaseOrder: "Purchase Orders"
        case .creditNote: "Credit Notes"
        case .deliveryChallan: "Delivery Challans"
        case .receipt: "Receipts"
        case .proposal: "Proposals"
        case .agreement: "Agreements"
        case .letter: "Letters"
        case .report: "Reports"
        case .custom: "Custom Documents"
        }
    }

    /// Top-level folder under `Documents/`.
    public var folderName: String { pluralName }

    public var defaultPrefix: String {
        switch self {
        case .invoice: "INV"
        case .quotation: "QUO"
        case .estimate: "EST"
        case .proformaInvoice: "PI"
        case .purchaseOrder: "PO"
        case .creditNote: "CN"
        case .deliveryChallan: "DC"
        case .receipt: "RCT"
        case .proposal: "PRP"
        case .agreement: "AGR"
        case .letter: "LTR"
        case .report: "RPT"
        case .custom: "DOC"
        }
    }

    public var category: DocumentCategory {
        switch self {
        case .quotation, .estimate, .proformaInvoice, .proposal: .sales
        case .invoice, .creditNote, .receipt: .finance
        case .purchaseOrder, .deliveryChallan: .purchase
        case .agreement, .letter, .report, .custom: .business
        }
    }

    /// Shown first in "Create New Document".
    public static let popular: [DocumentKind] = [.invoice, .quotation, .estimate, .purchaseOrder, .deliveryChallan, .creditNote]

    /// Has an items table. Proposals have both a body and an optional pricing table.
    public var usesLineItems: Bool {
        ![.receipt, .agreement, .letter, .report].contains(self)
    }

    /// Has a rich-text body edited like a word processor.
    public var usesBody: Bool {
        [.proposal, .agreement, .letter, .report].contains(self)
    }

    /// Amounts are meaningful. Challans list goods only; text documents carry no total.
    public var showsPricing: Bool {
        ![.deliveryChallan, .agreement, .letter, .report].contains(self)
    }

    /// Title printed on the document. Letters print none; text documents prefer their own title.
    public var documentTitle: String {
        switch self {
        case .invoice: "Invoice"
        case .receipt: "Payment Receipt"
        case .letter: ""
        default: displayName
        }
    }

    public var numberLabel: String {
        switch self {
        case .invoice: "Invoice No."
        case .quotation: "Quotation No."
        case .estimate: "Estimate No."
        case .proformaInvoice: "Proforma No."
        case .purchaseOrder: "PO No."
        case .creditNote: "Credit Note No."
        case .deliveryChallan: "Challan No."
        case .receipt: "Receipt No."
        case .proposal: "Proposal No."
        case .agreement: "Agreement No."
        case .letter: "Ref. No."
        case .report: "Report No."
        case .custom: "No."
        }
    }

    /// Heading of the counter-party block.
    public var partyLabel: String {
        switch self {
        case .purchaseOrder: "Vendor"
        case .deliveryChallan: "Deliver To"
        case .receipt: "Received From"
        case .creditNote: "Credit To"
        case .proposal, .report: "Prepared For"
        case .agreement: "Client"
        case .letter: "To"
        default: "Bill To"
        }
    }

    /// Label for the secondary date field.
    public var dueDateLabel: String? {
        switch self {
        case .invoice, .proformaInvoice: "Due date"
        case .quotation, .estimate, .proposal: "Valid until"
        case .purchaseOrder: "Delivery by"
        default: nil
        }
    }

    public var defaultDueDays: (CompanyProfile) -> Int? {
        switch self {
        case .invoice, .proformaInvoice: { $0.defaultPaymentTermsDays }
        case .quotation, .estimate, .proposal: { $0.defaultQuoteValidityDays }
        case .purchaseOrder: { _ in 7 }
        default: { _ in nil }
        }
    }

    /// Documents that can be turned into an invoice.
    public var convertsToInvoice: Bool { [.quotation, .estimate, .proformaInvoice, .proposal].contains(self) }

    /// Invoices accept recorded payments.
    public var acceptsPayments: Bool { self == .invoice }

    public var statuses: [DocumentStatus] {
        switch self {
        case .invoice: [.draft, .issued, .sent, .partiallyPaid, .paid, .overdue, .cancelled]
        case .quotation, .estimate, .proposal: [.draft, .issued, .sent, .accepted, .declined, .cancelled]
        case .proformaInvoice: [.draft, .issued, .sent, .accepted, .cancelled]
        case .purchaseOrder: [.draft, .issued, .sent, .confirmed, .delivered, .cancelled]
        case .deliveryChallan: [.draft, .issued, .delivered, .cancelled]
        case .agreement: [.draft, .issued, .sent, .signed, .cancelled]
        case .letter, .report: [.draft, .issued, .sent, .cancelled]
        case .custom: [.draft, .issued, .sent, .accepted, .cancelled]
        case .creditNote, .receipt: [.draft, .issued, .cancelled]
        }
    }
}

public enum DocumentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft
    case issued
    case sent
    case accepted
    case declined
    case confirmed
    case delivered
    case signed
    case partiallyPaid
    case paid
    case overdue
    case cancelled

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .draft: "Draft"
        case .issued: "Issued"
        case .sent: "Sent"
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .confirmed: "Confirmed"
        case .delivered: "Delivered"
        case .signed: "Signed"
        case .partiallyPaid: "Partially Paid"
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .cancelled: "Cancelled"
        }
    }

    /// Content of anything past draft is frozen; corrections go through a revision.
    public var isContentLocked: Bool { self != .draft }

    /// Invoice states that still count toward outstanding receivables.
    public var isOutstanding: Bool {
        [.issued, .sent, .partiallyPaid, .overdue].contains(self)
    }
}

public struct Address: Codable, Hashable, Sendable {
    public var line1: String = ""
    public var line2: String = ""
    public var city: String = ""
    public var state: String = ""
    public var postalCode: String = ""
    public var country: String = ""

    public init(line1: String = "", line2: String = "", city: String = "", state: String = "", postalCode: String = "", country: String = "") {
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }

    public var isEmpty: Bool { lines.isEmpty }

    public var lines: [String] {
        let cityLine = [city, [state, postalCode].filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return [line1, line2, cityLine, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var formatted: String { lines.joined(separator: "\n") }
}

public enum DiscountKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case percent
    case amount

    public var id: String { rawValue }
    public var displayName: String { self == .percent ? "%" : "Amount" }
}

public enum TaxMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case exclusive
    case inclusive

    public var id: String { rawValue }
    public var displayName: String { self == .exclusive ? "Prices exclude tax" : "Prices include tax" }
}

/// How tax is presented. Rates are always configured per line; nothing assumes a single national rate.
public enum TaxSplit: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case single
    case cgstSgst
    case igst

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "No tax"
        case .single: "Single tax (VAT / sales tax)"
        case .cgstSgst: "GST: CGST + SGST (intra-state)"
        case .igst: "GST: IGST (inter-state)"
        }
    }
}

public enum PageSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case a4
    case letter
    case a5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .a5: "A5"
        }
    }

    /// Portrait size in PDF points.
    public var points: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 419.53, height: 595.28)
        }
    }
}

public enum PageOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum PaymentMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case bankTransfer
    case upi
    case cash
    case cheque
    case card
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bankTransfer: "Bank transfer"
        case .upi: "UPI"
        case .cash: "Cash"
        case .cheque: "Cheque"
        case .card: "Card"
        case .other: "Other"
        }
    }
}
