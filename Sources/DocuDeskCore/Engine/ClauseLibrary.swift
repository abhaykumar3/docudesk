import Foundation

/// A reusable block of text (terms, legal clauses, standard paragraphs). Stored in the
/// workspace database so it travels with backups. Text uses the starter markup.
public struct Clause: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var text: String
    public var isBuiltIn: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, category: String, text: String, isBuiltIn: Bool = false, now: Date = Date()) {
        self.id = id
        self.title = title
        self.category = category
        self.text = text
        self.isBuiltIn = isBuiltIn
        updatedAt = now
    }
}

public enum ClauseLibrary {
    public static let categories = ["Payment", "Legal", "Delivery", "Confidentiality", "General"]

    /// Seeded into new workspaces; users can edit or delete them.
    public static let builtIn: [Clause] = [
        Clause(title: "Payment within 15 days", category: "Payment",
               text: "Payment is due within 15 days of the invoice date. Please quote the invoice number with your payment.", isBuiltIn: true),
        Clause(title: "Late payment interest", category: "Payment",
               text: "Overdue amounts attract interest at 1.5% per month from the due date until payment is received.", isBuiltIn: true),
        Clause(title: "Advance payment", category: "Payment",
               text: "An advance of 50% is payable on acceptance. The balance is payable on delivery.", isBuiltIn: true),
        Clause(title: "Prices exclusive of taxes", category: "Payment",
               text: "All prices are exclusive of applicable taxes, which will be charged at the prevailing rates.", isBuiltIn: true),
        Clause(title: "Quotation validity", category: "General",
               text: "This quotation is valid for 30 days from the date of issue. Prices may change after that.", isBuiltIn: true),
        Clause(title: "Delivery timeline", category: "Delivery",
               text: "Delivery timelines start after receipt of the advance payment and all required inputs from the client.", isBuiltIn: true),
        Clause(title: "Goods once sold", category: "Delivery",
               text: "Goods once sold will not be taken back or exchanged. Please check items at the time of delivery.", isBuiltIn: true),
        Clause(title: "Warranty", category: "Delivery",
               text: "Defects reported within 30 days of delivery will be corrected at no additional cost.", isBuiltIn: true),
        Clause(title: "Confidentiality", category: "Confidentiality",
               text: "Each party will keep the other party's confidential information secret and use it only for the purpose of this engagement.", isBuiltIn: true),
        Clause(title: "Intellectual property", category: "Legal",
               text: "On receipt of full payment, ownership of the final deliverables passes to the client. Pre-existing materials and third-party components remain with their owners.", isBuiltIn: true),
        Clause(title: "Limitation of liability", category: "Legal",
               text: "Neither party is liable for indirect or consequential loss. Total liability is limited to the fees paid under this engagement.", isBuiltIn: true),
        Clause(title: "Termination", category: "Legal",
               text: "Either party may terminate with 30 days' written notice. Work completed up to the termination date will be paid for.", isBuiltIn: true),
        Clause(title: "Jurisdiction", category: "Legal",
               text: "Any dispute is subject to the exclusive jurisdiction of the courts at [City].", isBuiltIn: true),
        Clause(title: "Force majeure", category: "Legal",
               text: "Neither party is responsible for delays caused by events beyond its reasonable control.", isBuiltIn: true),
    ]
}
