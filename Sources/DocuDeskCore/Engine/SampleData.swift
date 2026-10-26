import Foundation

/// Placeholder content for template previews and the gallery.
public enum SampleData {
    public static let companyID = UUID(uuidString: "00000000-0000-0000-0000-00000000D0C5")!

    public static var company: CompanyProfile {
        var company = CompanyProfile(id: companyID, name: "Your Company", now: Date(timeIntervalSince1970: 0))
        company.address = Address(line1: "123 Business Street", city: "New Delhi", state: "Delhi", postalCode: "110001", country: "India")
        company.email = "hello@yourcompany.com"
        company.phone = "+91 98765 43210"
        company.website = "www.yourcompany.com"
        company.taxID = "07ABCDE1234F1Z5"
        company.signatoryName = "John Doe"
        company.bankDetails = "Bank: HDFC Bank · A/C 50200012345678 · IFSC HDFC0001234\nUPI: yourcompany@hdfcbank"
        company.defaultTerms = "1. Payment is due within 15 days.\n2. Please include the invoice number in your payment reference."
        return company
    }

    public static func document(kind: DocumentKind, template: TemplateDefinition, company: CompanyProfile? = nil) -> DocumentRecord {
        let company = company ?? self.company
        var document = DocumentRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: kind,
            number: NumberingRule(prefix: kind.defaultPrefix).format(1, year: CalendarDate.today.year),
            company: company,
            template: template,
            issueDate: .today,
            now: Date(timeIntervalSince1970: 0)
        )
        var customer = PartyDetails(name: kind == .purchaseOrder ? "Metro Supplies" : "Acme Pvt. Ltd.")
        customer.billingAddress = Address(line1: "456 Client Avenue", city: "Mumbai", state: "Maharashtra", postalCode: "400001", country: "India")
        customer.email = "accounts@acme.example"
        document.customer = customer
        switch kind {
        case .receipt:
            document.receipt?.amountReceived = 53100
            document.receipt?.method = .bankTransfer
            document.receipt?.transactionReference = "UTR 4521 8890 1123"
            document.receipt?.againstDocumentNumber = NumberingRule(prefix: "INV").format(1, year: CalendarDate.today.year)
        default:
            document.items = [
                item("Website Development", "Responsive marketing site, 8 pages", 1, 25000, hsn: "998314"),
                item("UI/UX Design", "Wireframes and visual design", 1, 15000, hsn: "998391"),
                item("Domain & Hosting (1 Year)", "", 1, 5000, hsn: "998315"),
            ]
            document.terms = company.defaultTerms
        }
        if kind.usesBody, let starter = DocumentStarter.starters(for: kind).first {
            document.title = starter.title
            document.body = RichTextBody(attributed: RichTextBuilder.build(starter.markup, theme: template.theme))
            document.notes = ""
            document.terms = ""
            document.paymentDetails = ""
            if !kind.usesLineItems { document.items = [] }
        }
        return document
    }

    private static func item(_ name: String, _ details: String, _ quantity: Decimal, _ price: Decimal, hsn: String) -> LineItem {
        var item = LineItem(name: name, quantity: quantity, unitPrice: price, taxRate: 18)
        item.details = details
        item.hsnSac = hsn
        item.unit = "nos"
        return item
    }
}
