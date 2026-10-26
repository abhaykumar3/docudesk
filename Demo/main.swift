import DocuDeskCore
import Foundation

// Creates a workspace filled with realistic sample data for demos and screenshots.
//   swift run DocuDeskDemo ~/DocuDesk-Demo

guard CommandLine.arguments.count == 2 else {
    print("usage: DocuDeskDemo <folder>")
    exit(2)
}
let root = URL(fileURLWithPath: (CommandLine.arguments[1] as NSString).expandingTildeInPath)
guard !FileManager.default.fileExists(atPath: root.path) else {
    print("\(root.path) already exists; choose a new folder.")
    exit(1)
}

var profile = SampleData.company
profile.id = UUID()
profile.name = "Shree Tech Solutions"
profile.address = Address(line1: "12, MG Road", city: "Pune", state: "Maharashtra", postalCode: "411001", country: "India")
profile.taxID = "27ABCDE1234F1Z5"
profile.email = "accounts@shreetech.example"
let store = try WorkspaceStore.create(at: root, profile: profile)

func client(_ name: String, _ city: String, _ state: String) throws -> Customer {
    var customer = Customer(name: name)
    customer.billingAddress = Address(line1: "Plot 45, Business Park", city: city, state: state, country: "India")
    customer.email = "accounts@\(name.lowercased().filter(\.isLetter)).example"
    try store.saveCustomer(customer)
    return customer
}
let acme = try client("Acme Pvt. Ltd.", "Mumbai", "Maharashtra")
let tech = try client("Tech Solutions", "Bengaluru", "Karnataka")
let global = try client("Global Traders", "Delhi", "Delhi")
let metro = try client("Metro Supplies", "Pune", "Maharashtra")

for (name, price, sac) in [("Website Development", 25000, "998314"), ("UI/UX Design", 15000, "998391"), ("Domain & Hosting (1 Year)", 5000, "998315"), ("Annual Maintenance", 12000, "998713")] {
    var product = ProductService(name: name)
    product.price = Decimal(price)
    product.taxRate = 18
    product.hsnSac = sac
    product.isService = true
    try store.saveProduct(product)
}

func make(_ kind: DocumentKind, _ customer: Customer, daysAgo: Int, items: [(String, Decimal, Decimal)], status: DocumentStatus, style: TemplateStyle = .modern) throws {
    var document = try store.newDocument(kind: kind, templateID: TemplateLibrary.defaultTemplate(for: kind, style: style).id, customer: customer)
    document.issueDate = CalendarDate.today.adding(days: -daysAgo)
    if let due = kind.defaultDueDays(profile) { document.dueDate = document.issueDate.adding(days: due) }
    if customer.billingAddress.state != "Maharashtra" { document.taxSplit = .igst }
    document.items = items.map { name, quantity, price in
        var item = LineItem(name: name, quantity: quantity, unitPrice: price, taxRate: 18)
        item.unit = "nos"
        return item
    }
    document = try store.save(document)
    if status != .draft { try store.setStatus(status, for: document.id) }
}

try make(.invoice, acme, daysAgo: 2, items: [("Website Development", 1, 25000), ("UI/UX Design", 1, 15000), ("Domain & Hosting (1 Year)", 1, 5000)], status: .paid)
try make(.quotation, tech, daysAgo: 4, items: [("Mobile App Development", 1, 48000)], status: .sent, style: .corporate)
try make(.estimate, global, daysAgo: 6, items: [("ERP Integration", 1, 60000), ("Training (days)", 2, 6250)], status: .draft, style: .elegant)
try make(.purchaseOrder, metro, daysAgo: 8, items: [("Laptops", 2, 52000), ("Monitors", 3, 7000)], status: .confirmed, style: .classic)
try make(.deliveryChallan, acme, daysAgo: 10, items: [("Server rack", 1, 0), ("Network switch", 2, 0)], status: .delivered, style: .minimal)
try make(.invoice, tech, daysAgo: 40, items: [("Annual Maintenance", 1, 12000)], status: .sent)
try make(.invoice, global, daysAgo: 75, items: [("Consulting (hours)", 30, 2500)], status: .paid, style: .corporate)
try make(.invoice, acme, daysAgo: 130, items: [("Website Redesign", 1, 85000)], status: .paid)
// Phase 2: payments, tags and text documents.
var query = DocumentQuery()
query.kinds = [.invoice]
query.statuses = [.sent]
if let open = try store.search(query).first {
    try store.recordPayment(PaymentRecord(amount: 5000, method: .upi, reference: "UPI 2231"), toInvoice: open.id, createReceipt: true)
    try store.addTag("Retainer", to: [open.id])
}
var proposal = try store.newDocument(kind: .proposal, customer: tech, starter: DocumentStarter.starter(id: "proposal.business"))
proposal.items = [LineItem(name: "Discovery & design", quantity: 1, unitPrice: 40000, taxRate: 18), LineItem(name: "App development", quantity: 1, unitPrice: 120000, taxRate: 18)]
proposal.taxSplit = .igst
proposal = try store.save(proposal)
let agreement = try store.newDocument(kind: .agreement, templateID: TemplateLibrary.defaultTemplate(for: .agreement, style: .classic).id,
                                      customer: acme, starter: DocumentStarter.starter(id: "agreement.service"))
let letter = try store.newDocument(kind: .letter, customer: global, starter: DocumentStarter.starter(id: "letter.reminder"))
let report = try store.newDocument(kind: .report, templateID: TemplateLibrary.defaultTemplate(for: .report, style: .corporate).id,
                                   customer: tech, starter: DocumentStarter.starter(id: "report.project"))
// Phase 3: a custom document type with fields.
var workOrder = CustomDocumentType(name: "Work Order", prefix: "WO")
workOrder.partyLabel = "Customer"
workOrder.showsPricing = true
workOrder.fields = [
    CustomFieldDefinition(id: "site_address", label: "Site Address", type: .multiline, placement: .details),
    CustomFieldDefinition(id: "technician", label: "Technician", type: .text, placement: .meta),
    CustomFieldDefinition(id: "job_date", label: "Job Date", type: .date, placement: .details),
    { var field = CustomFieldDefinition(id: "priority", label: "Priority", type: .choice, placement: .details); field.choices = ["Low", "Normal", "Urgent"]; return field }(),
]
workOrder = try store.saveCustomType(workOrder)
var job = try store.newDocument(customType: workOrder, customer: metro)
job.items = [LineItem(name: "AC servicing (split unit)", quantity: 3, unitPrice: 1500, taxRate: 18), LineItem(name: "Gas top-up", quantity: 1, unitPrice: 2200, taxRate: 18)]
job.customFields = ["site_address": "Unit 4, Metro Warehouse, Hinjewadi Phase 2, Pune", "technician": "Ravi Kulkarni", "job_date": CalendarDate.today.adding(days: 3).iso, "priority": "Urgent"]
job = try store.save(job)
if CommandLine.arguments.contains("--pdfs") || ProcessInfo.processInfo.environment["DOCUDESK_DEMO_PDFS"] != nil {
    for document in [proposal, agreement, letter, report, job] { try store.exportPDF(document) }
}
print("Demo workspace created at \(root.path)")
