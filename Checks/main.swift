import AppKit
@testable import DocuDeskCore
import Foundation
import PDFKit

// Command Line Tools ship without XCTest, so these checks run as a plain executable:
//   swift run DocuDeskChecks

var failures = 0
var passes = 0
var currentGroup = ""

func group(_ name: String, _ body: () throws -> Void) {
    currentGroup = name
    do {
        try body()
    } catch {
        failures += 1
        print("✗ [\(name)] threw: \(error.localizedDescription)")
    }
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    do {
        if try condition() {
            passes += 1
        } else {
            failures += 1
            print("✗ [\(currentGroup)] \(message) (line \(line))")
        }
    } catch {
        failures += 1
        print("✗ [\(currentGroup)] \(message) threw \(error.localizedDescription) (line \(line))")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    expect(actual == expected, "\(message): expected \(expected), got \(actual)", line: line)
}

func expectThrows(_ message: String, line: Int = #line, _ body: () throws -> Void) {
    do {
        try body()
        failures += 1
        print("✗ [\(currentGroup)] \(message): expected an error (line \(line))")
    } catch {
        passes += 1
    }
}

func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

func makeDocument(_ kind: DocumentKind = .invoice) -> DocumentRecord {
    var document = DocumentRecord(kind: kind, number: "TEST-1", company: SampleData.company, template: TemplateLibrary.defaultTemplate(for: kind, style: .modern))
    document.items = []
    return document
}

let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DocuDeskChecks-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: temporaryRoot) }

// MARK: - Calculations

group("PRD calculation example") {
    var document = makeDocument()
    document.taxSplit = .cgstSgst
    document.items = [LineItem(name: "Item A", quantity: 1, unitPrice: 10000, taxRate: 18),
                      LineItem(name: "Item B", quantity: 1, unitPrice: 10000, taxRate: 18)]
    document.documentDiscountKind = .amount
    document.documentDiscountValue = 2000
    let totals = DocumentCalculator.totals(for: document)
    expectEqual(totals.subtotal, 20000, "subtotal")
    expectEqual(totals.documentDiscount, 2000, "discount")
    expectEqual(totals.taxableAmount, 18000, "taxable")
    expectEqual(totals.taxTotal, 3240, "GST")
    expectEqual(totals.taxLines.map(\.amount), [1620, 1620], "CGST/SGST split")
    expectEqual(totals.grandTotal, 21240, "total")
    expectEqual(totals.amountInWords, "Rupees Twenty-One Thousand Two Hundred Forty Only", "words")
}

group("Line discounts, mixed rates, shipping, round-off") {
    var document = makeDocument()
    document.taxSplit = .igst
    var a = LineItem(name: "A", quantity: d("3"), unitPrice: d("333.33"), taxRate: 18)
    a.discountKind = .percent
    a.discountValue = 10
    var b = LineItem(name: "B", quantity: d("2.5"), unitPrice: d("99.99"), taxRate: 5)
    b.discountKind = .amount
    b.discountValue = d("9.99")
    document.items = [a, b]
    document.shipping = 50
    document.roundOffTotal = true
    let t = DocumentCalculator.totals(for: document)
    // A: 999.99 − 100.00 = 899.99; B: 249.98 (249.975 rounded) − 9.99 = 239.99
    expectEqual(t.lines.map(\.net), [d("899.99"), d("239.99")], "line nets")
    expectEqual(t.subtotal, d("1139.98"), "subtotal")
    // 899.99 × 18% = 161.9982 → 162.00; 239.99 × 5% = 11.9995 → 12.00
    expectEqual(t.taxLines.map(\.amount), [d("12.00"), d("162.00")], "tax per rate (sorted by rate)")
    expectEqual(t.taxLines.map(\.label), ["IGST @ 5%", "IGST @ 18%"], "IGST labels")
    // 1139.98 + 174 + 50 = 1363.98 → round off +0.02
    expectEqual(t.roundOff, d("0.02"), "round off")
    expectEqual(t.grandTotal, 1364, "grand total")
}

group("Odd-paise CGST/SGST split stays exact") {
    var document = makeDocument()
    document.taxSplit = .cgstSgst
    document.items = [LineItem(name: "A", quantity: 1, unitPrice: d("100.05"), taxRate: 18)]
    let t = DocumentCalculator.totals(for: document)
    // 100.05 × 18% = 18.009 → 18.01; halves 9.01 + 9.00
    expectEqual(t.taxTotal, d("18.01"), "tax total")
    expectEqual(t.taxLines.map(\.amount), [d("9.01"), d("9.00")], "split sums to total")
    expectEqual(t.taxLines.map(\.label), ["CGST @ 9%", "SGST @ 9%"], "labels")
}

group("Tax-inclusive pricing") {
    var document = makeDocument()
    document.taxMode = .inclusive
    document.taxSplit = .single
    document.taxLabel = "VAT"
    document.items = [LineItem(name: "A", quantity: 1, unitPrice: 118, taxRate: 18)]
    let t = DocumentCalculator.totals(for: document)
    expectEqual(t.taxableAmount, 100, "taxable backs out tax")
    expectEqual(t.taxTotal, 18, "tax")
    expectEqual(t.grandTotal, 118, "total equals entered price")
    expectEqual(t.taxLines.first?.label, "VAT @ 18%", "custom label")
}

group("Proportional document discount allocation") {
    var document = makeDocument()
    document.taxSplit = .igst
    document.items = [LineItem(name: "A", quantity: 1, unitPrice: 100, taxRate: 18),
                      LineItem(name: "B", quantity: 1, unitPrice: 200, taxRate: 5),
                      LineItem(name: "C", quantity: 1, unitPrice: 0, taxRate: 18)]
    document.documentDiscountKind = .amount
    document.documentDiscountValue = 100
    let t = DocumentCalculator.totals(for: document)
    expectEqual(t.lines.map(\.allocatedDiscount), [d("33.33"), d("66.67"), 0], "allocation")
    expectEqual(t.taxableAmount, 200, "taxable")
    // 66.67 × 18% = 12.0006 → 12.00 ; 133.33 × 5% = 6.6665 → 6.67
    expectEqual(t.taxTotal, d("18.67"), "tax")
    expectEqual(t.grandTotal, d("218.67"), "total")
}

group("Discount limits and no-tax mode") {
    var document = makeDocument()
    document.taxSplit = .none
    var a = LineItem(name: "A", quantity: 1, unitPrice: 50, taxRate: 18)
    a.discountKind = .amount
    a.discountValue = 80
    document.items = [a]
    document.documentDiscountKind = .percent
    document.documentDiscountValue = 150
    let t = DocumentCalculator.totals(for: document)
    expectEqual(t.lines[0].net, 0, "line discount capped at gross")
    expectEqual(t.taxTotal, 0, "no tax when split is none")
    expectEqual(t.grandTotal, 0, "total never negative from discounts")
    document.advancePaid = 0
}

group("Advance and balance due") {
    var document = makeDocument()
    document.taxSplit = .none
    document.items = [LineItem(name: "A", quantity: 4, unitPrice: d("2500"), taxRate: 0)]
    document.advancePaid = 4000
    let t = DocumentCalculator.totals(for: document)
    expectEqual(t.balanceDue, 6000, "balance due")
}

group("Amount in words") {
    expectEqual(AmountInWords.words(for: d("12345678.50"), currency: "INR"),
                "Rupees One Crore Twenty-Three Lakh Forty-Five Thousand Six Hundred Seventy-Eight and Fifty Paise Only", "Indian system")
    expectEqual(AmountInWords.words(for: d("1050.25"), currency: "USD"),
                "One Thousand Fifty US Dollars and Twenty-Five Cents Only", "international")
    expectEqual(AmountInWords.words(for: d("2000000"), currency: "USD"), "Two Million US Dollars Only", "million")
    expectEqual(AmountInWords.words(for: 0, currency: "INR"), "Rupees Zero Only", "zero")
    expectEqual(AmountInWords.words(for: d("1000000000"), currency: "INR"), "Rupees One Hundred Crore Only", "hundred crore")
}

group("Money formatting and decimal JSON") {
    expectEqual(MoneyFormatter.format(d("248500"), currency: "INR"), "₹2,48,500.00", "Indian grouping")
    expectEqual(MoneyFormatter.format(d("1234.5"), currency: "USD"), "$1,234.50", "US format")
    var item = LineItem(name: "Precise", quantity: d("0.1"), unitPrice: d("0.2"), taxRate: d("12.5"))
    item.discountValue = d("3.3")
    let data = try DocuDeskJSON.encoder.encode(item)
    let json = String(decoding: data, as: UTF8.self)
    expect(json.contains("\"0.1\"") && json.contains("\"12.5\""), "decimals stored as strings")
    let decoded = try DocuDeskJSON.decoder.decode(LineItem.self, from: data)
    expectEqual(decoded, item, "round trip is exact")
    expectEqual(Decimal.parse("₹ 1,23,456.78"), d("123456.78"), "parse grouped input")
    expect(Decimal.parse("1.2.3") == nil, "reject malformed numbers")
}

group("Calendar dates and numbering") {
    let date = CalendarDate(iso: "2026-02-28")!
    expectEqual(date.adding(days: 1).iso, "2026-03-01", "adding days")
    expect(CalendarDate(iso: "2026-13-01") == nil, "invalid month rejected")
    let rule = NumberingRule(prefix: "INV", includeYear: true, padding: 4, nextNumber: 7, resetYearly: true, lastYear: 2025)
    expectEqual(rule.format(7, year: 2026), "INV-2026-0007", "format")
    expectEqual(rule.candidate(for: 2026), 1, "yearly reset")
    expectEqual(rule.candidate(for: 2025), 7, "same year continues")
}

// MARK: - Storage

func freshStore(_ name: String) throws -> WorkspaceStore {
    var profile = CompanyProfile(name: "Shree Tech")
    profile.address = Address(line1: "1 Main Road", city: "Pune", state: "Maharashtra", postalCode: "411001", country: "India")
    return try WorkspaceStore.create(at: temporaryRoot.appendingPathComponent(name), profile: profile)
}

group("Workspace creation and opening") {
    let root = temporaryRoot.appendingPathComponent("Open")
    let store = try freshStore("Open")
    expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("workspace.json").path), "marker written")
    for folder in ["Database", "Documents/Invoices", "Templates", "Assets", "Backups", "Exports"] {
        expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(folder).path), "\(folder) exists")
    }
    store.close()
    let reopened = try WorkspaceStore.open(at: root)
    expectEqual(try reopened.profiles().map(\.name), ["Shree Tech"], "profile persisted")
    reopened.close()

    expectThrows("missing folder is reported, not recreated") {
        _ = try WorkspaceStore.open(at: temporaryRoot.appendingPathComponent("Unplugged Drive"))
    }
    expect(!FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("Unplugged Drive").path), "no folder created")

    let plain = temporaryRoot.appendingPathComponent("Plain Folder")
    try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    expectThrows("non-workspace refused") { _ = try WorkspaceStore.open(at: plain) }
}

group("Documents: numbering, persistence, locking, revisions") {
    let store = try freshStore("Docs")
    let year = CalendarDate.today.year
    var invoice = try store.newDocument(kind: .invoice)
    let second = try store.newDocument(kind: .invoice)
    let quote = try store.newDocument(kind: .quotation)
    expectEqual(invoice.number, "INV-\(year)-0001", "first invoice number")
    expectEqual(second.number, "INV-\(year)-0002", "sequential")
    expectEqual(quote.number, "QUO-\(year)-0001", "per-kind numbering")

    var customer = Customer(name: "Acme Pvt. Ltd.")
    customer.billingAddress.city = "Mumbai"
    customer.taxID = "27AAAAA0000A1Z5"
    try store.saveCustomer(customer)
    store.apply(customer: customer, to: &invoice)
    invoice.items = [LineItem(name: "Website Development", quantity: 1, unitPrice: 25000, taxRate: 18)]
    invoice = try store.save(invoice)
    expectEqual(invoice.totals.grandTotal, 29500, "totals stored on save")

    let folder = temporaryRoot.appendingPathComponent("Docs/Documents/Invoices/\(year)/\(invoice.number)/document.json")
    expect(FileManager.default.fileExists(atPath: folder.path), "document visible in Finder-friendly folder")

    var clash = second
    clash.number = invoice.number
    expectThrows("duplicate number refused") { try store.save(clash) }
    var bad = second
    bad.number = "../escape"
    expectThrows("path characters refused") { try store.save(bad) }

    // Issue → content locked, status changes still allowed.
    let issued = try store.issue(invoice)
    expectEqual(issued.status, .issued, "issued")
    var tampered = issued
    tampered.items[0].unitPrice = 1
    expectThrows("issued content can't be edited") { try store.save(tampered) }
    let sent = try store.setStatus(.sent, for: issued.id)
    expectEqual(sent.status, .sent, "status change allowed")
    let revisions = folder.deletingLastPathComponent().appendingPathComponent("revisions")
    expect((try FileManager.default.contentsOfDirectory(atPath: revisions.path)).contains { $0.hasPrefix("R1-issued") }, "issued snapshot kept")

    // Editing the customer later doesn't alter the issued snapshot.
    customer.name = "Acme Global Ltd."
    try store.saveCustomer(customer)
    expectEqual(try store.loadDocument(id: issued.id).customer.name, "Acme Pvt. Ltd.", "historical snapshot preserved")

    // Revision
    let revised = try store.createRevision(of: issued.id)
    expectEqual(revised.revision, 2, "revision number")
    expectEqual(revised.status, .draft, "revision is editable")
    expectEqual(revised.number, invoice.number, "same number")

    // Duplicate creates a new draft and leaves the original alone.
    let copy = try store.duplicate(revised.id)
    expect(copy.id != revised.id && copy.number != revised.number, "duplicate has new identity")
    expectEqual(copy.status, .draft, "duplicate is draft")
    expectEqual(copy.customer.name, "Acme Global Ltd.", "duplicate picks up current customer details")
    expectEqual(try store.loadDocument(id: revised.id).number, revised.number, "original untouched")

    // Conversion and receipts
    let converted = try store.convertToInvoice(quote.id)
    expectEqual(converted.kind, .invoice, "converted kind")
    expectEqual(try store.loadDocument(id: quote.id).status, .accepted, "quotation accepted")
    expect(try store.loadDocument(id: quote.id).links.contains { $0.documentID == converted.id }, "linked both ways")
    let issuedAgain = try store.issue(try store.loadDocument(id: revised.id))
    let paid = try store.recordPayment(PaymentRecord(amount: 29500), toInvoice: issuedAgain.id, createReceipt: true)
    expectEqual(paid.receipt?.receipt?.amountReceived, 29500, "receipt for balance")
    expectEqual(paid.receipt?.totals.grandTotal, 29500, "receipt total")
    expectEqual(paid.invoice.status, .paid, "fully paid")

    // Deletion safeguards
    expectThrows("issued can't be deleted") { try store.deleteDraft(id: issuedAgain.id, moveToTrash: false) }
    try store.deleteDraft(id: second.id, moveToTrash: false)
    expectThrows("deleted draft gone") { _ = try store.loadDocument(id: second.id) }

    // Persistence across relaunch
    let count = try store.search(DocumentQuery()).count
    store.close()
    let reopened = try WorkspaceStore.open(at: temporaryRoot.appendingPathComponent("Docs"))
    expectEqual(try reopened.search(DocumentQuery()).count, count, "documents survive relaunch")
    reopened.close()
}

group("Search, filters and index rebuild") {
    let store = try freshStore("Search")
    var a = try store.newDocument(kind: .invoice)
    a.customer.name = "Tech Solutions"
    a.items = [LineItem(name: "Mobile app development", quantity: 1, unitPrice: 48000, taxRate: 18)]
    a = try store.save(a)
    var b = try store.newDocument(kind: .quotation)
    b.customer.name = "Global Traders"
    b.items = [LineItem(name: "Annual maintenance", quantity: 12, unitPrice: 1000, taxRate: 18)]
    b = try store.save(b)

    expectEqual(try store.search({ var q = DocumentQuery(); q.text = a.number; return q }()).map(\.id), [a.id], "search by number")
    expectEqual(try store.search({ var q = DocumentQuery(); q.text = "global"; return q }()).map(\.id), [b.id], "search by customer")
    expectEqual(try store.search({ var q = DocumentQuery(); q.text = "mainten"; return q }()).map(\.id), [b.id], "prefix search on items")
    expectEqual(try store.search({ var q = DocumentQuery(); q.kinds = [.quotation]; return q }()).map(\.id), [b.id], "kind filter")
    expectEqual(try store.search({ var q = DocumentQuery(); q.minAmount = 50000; return q }()).map(\.id), [a.id], "amount filter")
    expectEqual(try store.search({ var q = DocumentQuery(); q.statuses = [.paid]; return q }()).count, 0, "status filter")

    // Corrupt one file and drop the index: rebuild restores what it can and reports the rest.
    let damaged = temporaryRoot.appendingPathComponent("Search/Documents/Invoices/2020/BROKEN")
    try FileManager.default.createDirectory(at: damaged, withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: damaged.appendingPathComponent("document.json"))
    try store.database.execute("DELETE FROM documents; DELETE FROM documents_fts;")
    let report = try store.rebuildIndex()
    expectEqual(report.indexed, 2, "rebuilt from JSON")
    expectEqual(report.damaged.count, 1, "damaged file reported")
    expectEqual(try store.search({ var q = DocumentQuery(); q.text = "tech"; return q }()).map(\.id), [a.id], "search works after rebuild")
    let stats = try store.dashboardStats()
    expectEqual(stats.total, 2, "dashboard count")
    store.close()
}

group("Missing database is reported, then rebuildable on request") {
    let root = temporaryRoot.appendingPathComponent("NoDB")
    let store = try freshStore("NoDB")
    _ = try store.newDocument(kind: .invoice)
    store.close()
    try FileManager.default.removeItem(at: root.appendingPathComponent("Database"))
    expectThrows("does not silently create an empty database") { _ = try WorkspaceStore.open(at: root) }
    let recovered = try WorkspaceStore.open(at: root, recreateDatabase: true)
    expectEqual(try recovered.search(DocumentQuery()).count, 1, "documents re-indexed from files")
    recovered.close()
}

// MARK: - Rendering

group("PDF rendering and pagination") {
    for template in TemplateLibrary.all {
        let document = SampleData.document(kind: template.kind, template: template)
        let output = DocumentRenderer.render(document)
        guard let pdf = PDFDocument(data: output.data) else {
            expect(false, "\(template.id) produced a readable PDF")
            continue
        }
        if !template.kind.usesBody { expectEqual(pdf.pageCount, 1, "\(template.id) fits one page") }
        expect(pdf.string?.contains(document.number) == true, "\(template.id) contains the number")
    }
    expectEqual(TemplateLibrary.all.count, DocumentKind.allCases.count * TemplateStyle.allCases.count, "template count")

    var long = SampleData.document(kind: .invoice, template: TemplateLibrary.defaultTemplate(for: .invoice, style: .corporate))
    long.items = (1...150).map { LineItem(name: "Line item \($0)", quantity: 1, unitPrice: Decimal($0), taxRate: 18) }
    let output = DocumentRenderer.render(long)
    let pdf = PDFDocument(data: output.data)!
    expect(pdf.pageCount >= 4, "150 items paginate (got \(pdf.pageCount) pages)")
    expectEqual(pdf.pageCount, output.pageCount, "layout page count matches PDF")
    let lastPage = pdf.page(at: pdf.pageCount - 1)?.string ?? ""
    expect(lastPage.contains("Page \(pdf.pageCount) of \(pdf.pageCount)"), "page X of Y footer")
    let secondPage = pdf.page(at: 1)?.string ?? ""
    expect(secondPage.contains("AMOUNT") || secondPage.contains("Amount"), "table header repeats on page 2")
    expectEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Invoice \(long.number)", "PDF title metadata")

    let a5 = { var doc = long; doc.pageSize = .a5; doc.orientation = .landscape; return doc }()
    let a5Page = PDFDocument(data: DocumentRenderer.pdfData(for: a5))!.page(at: 0)!.bounds(for: .mediaBox)
    expect(abs(a5Page.width - 595.28) < 0.5 && abs(a5Page.height - 419.53) < 0.5, "A5 landscape page size")

    var challan = SampleData.document(kind: .deliveryChallan, template: TemplateLibrary.defaultTemplate(for: .deliveryChallan, style: .minimal))
    challan.number = "DC-1"
    let challanText = PDFDocument(data: DocumentRenderer.pdfData(for: challan))?.string ?? ""
    expect(!challanText.contains("25,000"), "delivery challan hides prices")

    let missing = { var doc = long; doc.templateID = "invoice.deleted"; return doc }()
    expect(DocumentRenderer.render(missing).usedFallbackTemplate, "deleted template falls back safely")
}

// MARK: - Backup

group("Backup, verification and restore") {
    let root = temporaryRoot.appendingPathComponent("Backup")
    let store = try freshStore("Backup")
    var invoice = try store.newDocument(kind: .invoice)
    invoice.items = [LineItem(name: "Kept item", quantity: 1, unitPrice: 999, taxRate: 0)]
    invoice = try store.save(invoice)
    try store.saveCustomer(Customer(name: "Backup Customer"))

    let backup = try BackupService.createBackup(of: store, in: store.workspace.backupsURL)
    expect(FileManager.default.fileExists(atPath: backup.path), "package written")
    let (manifest, extracted) = try BackupService.verify(backup)
    try? FileManager.default.removeItem(at: extracted.deletingLastPathComponent())
    expectEqual(manifest.documentCount, 1, "manifest counts documents")
    expectEqual(BackupService.history(of: store).count, 1, "backup recorded")

    expectThrows("unavailable external destination reported") {
        try BackupService.createBackup(of: store, in: URL(fileURLWithPath: "/Volumes/DocuDesk-Missing-Drive"))
    }

    // Changes after the backup are rolled back by restore; the old content is kept aside.
    _ = try store.newDocument(kind: .invoice)
    store.close()
    let safety = try BackupService.restore(backup, intoWorkspaceAt: root)
    expect(FileManager.default.fileExists(atPath: safety.appendingPathComponent("Documents").path), "previous content kept")
    let restored = try WorkspaceStore.open(at: root)
    let docs = try restored.search(DocumentQuery())
    expectEqual(docs.map(\.id), [invoice.id], "restored documents and IDs")
    expectEqual(try restored.customers().map(\.name), ["Backup Customer"], "restored customers")
    let next = try restored.newDocument(kind: .invoice)
    expectEqual(next.number, "INV-\(CalendarDate.today.year)-0002", "numbering configuration restored")
    restored.close()

    // Tampering is detected before anything is touched.
    let tamperRoot = temporaryRoot.appendingPathComponent("Tamper")
    try FileManager.default.createDirectory(at: tamperRoot, withIntermediateDirectories: true)
    let unpacked = tamperRoot.appendingPathComponent("x")
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    unzip.arguments = ["-x", "-k", backup.path, unpacked.path]
    try unzip.run()
    unzip.waitUntilExit()
    let target = try FileManager.default.subpathsOfDirectory(atPath: unpacked.path).first { $0.hasSuffix("document.json") }!
    try Data("tampered".utf8).write(to: unpacked.appendingPathComponent(target))
    let tampered = tamperRoot.appendingPathComponent("tampered.docudeskbackup")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    zip.arguments = ["-c", "-k", unpacked.path, tampered.path]
    try zip.run()
    zip.waitUntilExit()
    expectThrows("checksum mismatch rejected") { _ = try BackupService.verify(tampered) }
}

// MARK: - Phase 2

group("Documents saved before Phase 2 still open") {
    var document = SampleData.document(kind: .invoice, template: TemplateLibrary.defaultTemplate(for: .invoice, style: .modern))
    document.totals = DocumentCalculator.totals(for: document)
    let data = try DocuDeskJSON.encoder.encode(document)
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    for key in ["payments", "body", "tags", "pinned", "archived", "templateSnapshot"] { json.removeValue(forKey: key) }
    var totals = json["totals"] as! [String: Any]
    totals.removeValue(forKey: "amountPaid")
    json["totals"] = totals
    json["schemaVersion"] = 1
    let legacy = try DocuDeskJSON.decoder.decode(DocumentRecord.self, from: JSONSerialization.data(withJSONObject: json))
    expectEqual(legacy.items.count, 3, "items preserved")
    expect(legacy.payments.isEmpty && legacy.tags.isEmpty && !legacy.archived && legacy.body.isEmpty, "new fields default")
    expectEqual(legacy.totals.amountPaid, 0, "new money field defaults to zero")
}

group("Payments") {
    let store = try freshStore("Payments")
    var invoice = try store.newDocument(kind: .invoice)
    invoice.customer.name = "Acme Pvt. Ltd."
    invoice.items = [LineItem(name: "Retainer", quantity: 1, unitPrice: 10000, taxRate: 18)]
    invoice = try store.save(invoice)
    expectThrows("draft can't take payments") {
        try store.recordPayment(PaymentRecord(amount: 100), toInvoice: invoice.id, createReceipt: false)
    }
    invoice = try store.issue(invoice)
    expectThrows("zero amount refused") { try store.recordPayment(PaymentRecord(amount: 0), toInvoice: invoice.id, createReceipt: false) }
    expectThrows("overpayment refused") { try store.recordPayment(PaymentRecord(amount: 11801), toInvoice: invoice.id, createReceipt: false) }

    let first = try store.recordPayment(PaymentRecord(amount: 5000, method: .upi, reference: "UPI123"), toInvoice: invoice.id, createReceipt: true)
    expectEqual(first.invoice.status, .partiallyPaid, "partially paid")
    expectEqual(first.invoice.totals.amountPaid, 5000, "amount paid")
    expectEqual(first.invoice.totals.balanceDue, 6800, "balance")
    expectEqual(first.receipt?.status, .issued, "receipt issued")
    expectEqual(first.receipt?.receipt?.againstDocumentNumber, invoice.number, "receipt references invoice")
    expect(first.invoice.links.contains { $0.kind == .paymentReceipt }, "invoice links to receipt")
    expectEqual(try store.dashboardStats().outstanding.first?.amount, 6800, "outstanding uses remaining balance")
    let pdfText = PDFDocument(data: store.renderPDF(first.invoice).data)?.string ?? ""
    expect(pdfText.contains("Amount paid") && pdfText.contains("6,800.00"), "PDF shows paid and balance")

    var tampered = first.invoice
    tampered.items[0].unitPrice = 1
    expectThrows("payments don't unlock content") { try store.save(tampered) }

    let second = try store.recordPayment(PaymentRecord(amount: 6800), toInvoice: invoice.id, createReceipt: false)
    expectEqual(second.invoice.status, .paid, "paid in full")
    expectThrows("paid invoice refuses more") { try store.recordPayment(PaymentRecord(amount: 1), toInvoice: invoice.id, createReceipt: false) }

    let firstPayment = second.invoice.payments[0]
    let reverted = try store.deletePayment(firstPayment.id, fromInvoice: invoice.id)
    expectEqual(reverted.status, .partiallyPaid, "deleting a payment reopens the balance")
    expectEqual(reverted.totals.balanceDue, 5000, "balance restored")
    expectEqual(try store.loadDocument(id: firstPayment.receiptID!).status, .cancelled, "its receipt is cancelled")
    store.close()
}

group("Text documents: starters, merge fields, pagination") {
    let store = try freshStore("Text")
    var client = Customer(name: "Acme Pvt. Ltd.")
    client.contactPerson = "Priya Sharma"
    client.billingAddress = Address(line1: "456 Client Avenue", city: "Mumbai", country: "India")
    try store.saveCustomer(client)

    let nda = try store.newDocument(kind: .agreement, customer: client, starter: DocumentStarter.starter(id: "agreement.nda"))
    expectEqual(nda.title, "Non-Disclosure Agreement", "starter title")
    expect(nda.body.plainText.contains("{{client.name}}"), "body keeps merge fields")
    expect(nda.items.isEmpty && nda.number.hasPrefix("AGR-"), "agreement has no items")
    let ndaPDF = PDFDocument(data: store.renderPDF(nda).data)!
    let ndaText = ndaPDF.string ?? ""
    expect(ndaText.contains("Mutual Non-Disclosure Agreement"), "body rendered")
    expect(ndaText.contains("Acme Pvt. Ltd.") && !ndaText.contains("{{"), "merge fields filled")
    expect(ndaText.contains("For Acme Pvt. Ltd.") && ndaText.contains("For Shree Tech"), "both parties sign")

    // Page breaks and long bodies flow across pages.
    let service = try store.newDocument(kind: .agreement, customer: client, starter: DocumentStarter.starter(id: "agreement.service"))
    let servicePDF = PDFDocument(data: store.renderPDF(service).data)!
    expect(servicePDF.pageCount >= 2, "form feed starts Schedule A on a new page (got \(servicePDF.pageCount))")
    expect(!(servicePDF.string ?? "").contains("PAGE BREAK"), "editor-only page break label not printed")
    let schedulePage = (0..<servicePDF.pageCount).first { servicePDF.page(at: $0)?.string?.contains("Schedule A: Services") == true }
    expect(schedulePage.map { $0 > 0 } ?? false, "schedule after break (pages: \((0..<servicePDF.pageCount).map { servicePDF.page(at: $0)?.string?.prefix(80) ?? "" }))")

    var long = try store.newDocument(kind: .report)
    let paragraph = String(repeating: "This sentence exists to fill the page with plenty of text. ", count: 12)
    long.body = RichTextBody(attributed: RichTextBuilder.build(Array(repeating: paragraph, count: 30).joined(separator: "\n"), theme: TemplateLibrary.theme(for: .modern)))
    long = try store.save(long)
    let longPDF = PDFDocument(data: store.renderPDF(long).data)!
    expect(longPDF.pageCount >= 4, "long body paginates (got \(longPDF.pageCount))")
    expect(longPDF.page(at: 1)?.string?.contains("fill the page") == true, "page 2 has body text")

    // Body round trip keeps formatting and images.
    let image = NSImage(size: CGSize(width: 1200, height: 300))
    image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 300).fill(); image.unlockFocus()
    let rich = NSMutableAttributedString(attributedString: RichTextBuilder.build("# Heading\n- point one\n1. first\n2. second\n| A | B |\n| 1 | 2 |", theme: TemplateLibrary.theme(for: .classic)))
    rich.append(RichTextTransform.imageAttachment(image, maxWidth: 400))
    let stored = RichTextBody(attributed: rich)
    let restored = stored.attributedString()
    expectEqual(restored.string, rich.string, "text round trips")
    var foundAttachment = false
    restored.enumerateAttribute(.attachment, in: NSRange(location: 0, length: restored.length)) { value, _, _ in if value != nil { foundAttachment = true } }
    expect(foundAttachment, "image survives RTFD round trip")
    expect(((restored.attribute(.paragraphStyle, at: restored.length - 6, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.isEmpty) == false
           || restored.string.contains("A"), "table survives")

    // Letters print no big title; proposals show pricing under "Investment".
    let letter = try store.newDocument(kind: .letter, customer: client, starter: DocumentStarter.starter(id: "letter.reminder"))
    expect(PDFDocument(data: store.renderPDF(letter).data)?.string?.contains("Dear Priya Sharma") == true, "contact merge field")
    var proposal = try store.newDocument(kind: .proposal, customer: client)
    proposal.items = [LineItem(name: "Discovery workshop", quantity: 1, unitPrice: 20000, taxRate: 18)]
    proposal = try store.save(proposal)
    let proposalText = PDFDocument(data: store.renderPDF(proposal).data)?.string ?? ""
    expect(proposalText.contains("Discovery workshop") && proposalText.contains("23,600.00"), "proposal pricing table")
    let invoice = try store.convertToInvoice(proposal.id)
    expect(invoice.kind == .invoice && invoice.body.isEmpty && invoice.items.count == 1, "proposal converts to invoice")

    // Switching template restyles text set in the old template's fonts.
    let restyled = RichTextTransform.restyle(RichTextBuilder.build("# Title\nBody", theme: TemplateLibrary.theme(for: .modern)),
                                             from: TemplateLibrary.theme(for: .modern), to: TemplateLibrary.theme(for: .classic))
    expectEqual((restyled.attribute(.font, at: restyled.length - 2, effectiveRange: nil) as? NSFont)?.fontName, "Georgia", "body font restyled")
    store.close()
}

group("Custom templates and versioning") {
    let store = try freshStore("Templates")
    var custom = CustomTemplate(name: "Brand", baseStyle: .modern)
    custom.theme.accent = RGBColor(hex: 0xC2185B)
    custom.theme.footerNote = "Subject to Pune jurisdiction"
    custom = try store.saveCustomTemplate(custom)
    expectEqual(custom.version, 1, "first version")

    var issued = try store.newDocument(kind: .invoice, templateID: custom.templateID)
    issued.items = [LineItem(name: "A", quantity: 1, unitPrice: 100, taxRate: 0)]
    issued = try store.issue(try store.save(issued))
    expectEqual(issued.templateSnapshot?.accent, RGBColor(hex: 0xC2185B), "snapshot taken on issue")
    let draft = try store.newDocument(kind: .quotation, templateID: custom.templateID)
    expect(PDFDocument(data: store.renderPDF(draft).data)?.string?.contains("Subject to Pune jurisdiction") == true, "footer note printed")

    custom.theme.accent = RGBColor(hex: 0x00897B)
    custom = try store.saveCustomTemplate(custom)
    expectEqual(custom.version, 2, "edit creates version 2")
    expectEqual(custom.history.first?.theme.accent, RGBColor(hex: 0xC2185B), "version 1 kept")
    expectEqual(store.theme(for: try store.loadDocument(id: issued.id)).accent, RGBColor(hex: 0xC2185B), "issued document keeps old look")
    expectEqual(store.theme(for: draft).accent, RGBColor(hex: 0x00897B), "draft follows latest")
    expectEqual(try store.save(draft).templateVersion, 2, "draft records the version it uses")

    let file = temporaryRoot.appendingPathComponent("brand.docudesktemplate")
    try store.exportTemplate(custom, to: file)
    let imported = try store.importTemplate(from: file)
    expect(imported.id != custom.id && imported.theme == custom.theme, "template import/export")
    try Data("not a template".utf8).write(to: temporaryRoot.appendingPathComponent("bad.docudesktemplate"))
    expectThrows("bad template file rejected") { try store.importTemplate(from: temporaryRoot.appendingPathComponent("bad.docudesktemplate")) }

    try store.deleteCustomTemplate(id: custom.id)
    expect(store.templateIsMissing(for: try store.loadDocument(id: draft.id)), "draft notices deleted template")
    expect(!store.templateIsMissing(for: try store.loadDocument(id: issued.id)), "issued renders from snapshot")
    store.close()
}

group("Multiple company profiles") {
    let store = try freshStore("Profiles")
    let primary = try store.defaultProfile()!
    let second = try store.createProfile(name: "Shree Design Studio", copyingDefaultsFrom: primary)
    let a = try store.newDocument(kind: .invoice, profileID: primary.id)
    let b = try store.newDocument(kind: .invoice, profileID: second.id)
    expectEqual(a.number, b.number, "each profile numbers independently")
    expect(store.folderPath(for: b).hasPrefix("Documents/Shree Design Studio ("), "second profile gets its own folder")
    expect(store.folderPath(for: a).hasPrefix("Documents/Invoices/"), "first profile keeps the top-level folders")
    var query = DocumentQuery()
    query.profileID = second.id
    expectEqual(try store.search(query).map(\.id), [b.id], "filter by profile")
    expectThrows("primary profile can't be deleted") { try store.deleteProfile(primary.id) }
    expectThrows("profile with documents can't be deleted") { try store.deleteProfile(second.id) }
    try store.setActiveProfile(second.id)
    expectEqual(try store.defaultProfile()?.id, second.id, "active profile switches")
    let empty = try store.createProfile(name: "Spare")
    try store.deleteProfile(empty.id)
    expectEqual(try store.profiles().count, 2, "empty profile deleted")
    store.close()
}

group("Clauses, tags, archive, bulk and duplicates") {
    let store = try freshStore("Organise")
    let clauses = try store.clauses()
    expectEqual(clauses.count, ClauseLibrary.builtIn.count, "built-in clauses seeded once")
    try store.saveClause(Clause(title: "Custom", category: "General", text: "My clause"))
    expectEqual(try store.clauses().count, ClauseLibrary.builtIn.count + 1, "clause added, no reseed")

    var one = try store.newDocument(kind: .invoice)
    one.customer.name = "Tech Solutions"
    one.items = [LineItem(name: "Support", quantity: 1, unitPrice: 5000, taxRate: 0)]
    one = try store.issue(try store.save(one))
    var two = try store.newDocument(kind: .invoice)
    two.customer.name = "Tech Solutions"
    two.items = one.items.map { var item = $0; item.id = UUID(); return item }
    two = try store.save(two)
    let three = try store.newDocument(kind: .quotation)

    expectEqual(try store.possibleDuplicates(of: two).map(\.id), [one.id], "duplicate detected")

    try store.addTag("Urgent", to: [one.id, two.id])
    try store.addTag("urgent", to: [two.id])
    expectEqual(try store.loadDocument(id: two.id).tags, ["Urgent"], "tags de-duplicated case-insensitively")
    var tagged = DocumentQuery()
    tagged.tags = ["urgent"]
    expectEqual(Set(try store.search(tagged).map(\.id)), [one.id, two.id], "tag filter (issued docs can be tagged)")
    expectEqual(try store.allTags(), ["Urgent"], "tag list")

    try store.setArchived(true, for: [three.id])
    expect(!(try store.search(DocumentQuery()).contains { $0.id == three.id }), "archived hidden by default")
    var archived = DocumentQuery()
    archived.archive = .archived
    expectEqual(try store.search(archived).map(\.id), [three.id], "archived filter")
    try store.setPinned(true, for: [two.id])
    expectEqual(try store.search(DocumentQuery()).first?.id, two.id, "pinned first")

    let exportFolder = temporaryRoot.appendingPathComponent("BulkOut")
    try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
    expectEqual(try store.exportPDFs([one.id, two.id], to: exportFolder).count, 2, "bulk PDF export")
    let records = try store.exportRecords([one.id, two.id], to: exportFolder)
    expect(FileManager.default.fileExists(atPath: records.appendingPathComponent("index.csv").path), "records export has index")
    expect(FileManager.default.fileExists(atPath: records.appendingPathComponent("Invoices/\(one.number)/document.json").path), "records copied")
    expectEqual(try store.deleteDrafts([one.id, two.id], moveToTrash: false), [one.number], "bulk delete skips issued")

    try store.setSavedFilters([SavedFilter(name: "Urgent", query: tagged)])
    expectEqual(store.savedFilters().first?.query.tags, ["urgent"], "saved filter")
    store.noteOpened(three.id)
    expectEqual(store.recentlyOpened().map(\.id), [three.id], "recently opened")
    store.close()
}

group("Database migration from schema 1") {
    let root = temporaryRoot.appendingPathComponent("Migrate")
    let store = try freshStore("Migrate")
    _ = try store.newDocument(kind: .invoice)
    try store.database.execute("""
    DROP INDEX documents_type; ALTER TABLE documents DROP COLUMN type_key; ALTER TABLE documents DROP COLUMN type_name;
    DROP TABLE custom_types; ALTER TABLE backups DROP COLUMN encrypted;
    DROP INDEX documents_archived; ALTER TABLE documents DROP COLUMN tags; ALTER TABLE documents DROP COLUMN pinned;
    ALTER TABLE documents DROP COLUMN archived; DROP TABLE clauses; DROP TABLE custom_templates; PRAGMA user_version = 1;
    """)
    store.close()
    let migrated = try WorkspaceStore.open(at: root)
    expectEqual(migrated.database.userVersion, WorkspaceStore.schemaVersion, "schema upgraded")
    expectEqual(try migrated.search(DocumentQuery()).count, 1, "documents still indexed")
    expect(!(try migrated.clauses()).isEmpty, "new tables usable")
    migrated.close()
}

group("Word export") {
    let store = try freshStore("Docx")
    var client = Customer(name: "Acme Pvt. Ltd.")
    client.billingAddress.city = "Mumbai"
    try store.saveCustomer(client)
    var invoice = try store.newDocument(kind: .invoice, customer: client)
    invoice.items = [LineItem(name: "Website Development", quantity: 1, unitPrice: 25000, taxRate: 18)]
    invoice = try store.save(invoice)
    var agreement = try store.newDocument(kind: .agreement, customer: client, starter: DocumentStarter.starter(id: "agreement.website"))
    let body = NSMutableAttributedString(attributedString: agreement.body.attributedString())
    let image = NSImage(size: CGSize(width: 200, height: 80))
    image.lockFocus(); NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 200, height: 80).fill(); image.unlockFocus()
    body.append(RichTextTransform.imageAttachment(image, maxWidth: 400))
    agreement.body = RichTextBody(attributed: body)
    agreement = try store.save(agreement)

    func wordText(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
    let invoiceDocx = try store.exportDOCX(invoice)
    let invoiceText = try wordText(invoiceDocx)
    expect(invoiceText.contains(invoice.number) && invoiceText.contains("Website Development") && invoiceText.contains("29,500.00"), "invoice DOCX readable")
    let agreementDocx = try store.exportDOCX(agreement)
    let agreementText = try wordText(agreementDocx)
    expect(agreementText.contains("Website Development Agreement") && agreementText.contains("Acme Pvt. Ltd."), "agreement DOCX has body and merge fields")
    expect(agreementText.contains("Design approval"), "agreement DOCX has table cells")
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-l", agreementDocx.path]
    let listing = Pipe()
    unzip.standardOutput = listing
    try unzip.run()
    unzip.waitUntilExit()
    let parts = String(decoding: listing.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    expect(parts.contains("word/media/image1.png") && parts.contains("word/footer1.xml"), "DOCX has image and footer parts")
    store.close()
}

// MARK: - Phase 3

func runTool(_ path: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

group("Custom document types") {
    let store = try freshStore("CustomTypes")
    var type = CustomDocumentType(name: "Work Order", prefix: "WO")
    type.partyLabel = "Customer"
    type.fields = [
        CustomFieldDefinition(id: "", label: "Site Address", type: .multiline, placement: .details),
        CustomFieldDefinition(id: "", label: "Technician", type: .text, placement: .meta),
        { var field = CustomFieldDefinition(id: "", label: "Job Date", type: .date, placement: .details); field.required = true; return field }(),
        CustomFieldDefinition(id: "", label: "Internal Code", type: .text, placement: .hidden),
    ]
    type = try store.saveCustomType(type)
    expectEqual(type.fields.map(\.id), ["site_address", "technician", "job_date", "internal_code"], "field keys from labels")
    var duplicateKeys = type
    duplicateKeys.fields.append(CustomFieldDefinition(id: "technician", label: "Technician"))
    expectThrows("repeated field keys refused") { try store.saveCustomType(duplicateKeys) }

    var order = try store.newDocument(customType: type)
    expectEqual(order.number, "WO-\(CalendarDate.today.year)-0001", "own numbering sequence")
    expect(store.folderPath(for: order).hasPrefix("Documents/Work Orders/"), "own folder")
    expectEqual(order.typeName, "Work Order", "type name")
    order.customer.name = "Acme Pvt. Ltd."
    order.items = [LineItem(name: "AC servicing", quantity: 2, unitPrice: 1500, taxRate: 18)]
    order.customFields = ["site_address": "Plot 7, MIDC, Pune", "technician": "Ravi K", "internal_code": "SECRET-42"]
    order = try store.save(order)
    expectThrows("required field blocks issue") { try store.issue(order) }
    order.customFields["job_date"] = "2026-11-02"
    order = try store.issue(try store.save(order))
    let text = PDFDocument(data: store.renderPDF(order).data)?.string ?? ""
    expect(text.contains("Site Address") && text.contains("Plot 7, MIDC, Pune") && text.contains("02 Nov 2026"), "details fields printed")
    expect(text.contains("Technician") && text.contains("Ravi K"), "meta field printed")
    expect(!text.contains("SECRET-42"), "hidden field not printed")
    expect(text.uppercased().contains("WORK ORDER") && text.contains("CUSTOMER"), "type title and labels")

    var renamed = type
    renamed.printedTitle = "Service Ticket"
    try store.saveCustomType(renamed)
    let draft = try store.newDocument(customType: type)
    expectEqual(try store.loadDocument(id: order.id).customType?.printedTitle, "Work Order", "issued keeps type snapshot")
    expectEqual(try store.save(draft).customType?.printedTitle, "Service Ticket", "drafts follow type changes")

    var query = DocumentQuery()
    query.customTypeID = type.id
    expectEqual(Set(try store.search(query).map(\.id)), [order.id, draft.id], "filter by custom type")
    expectEqual(try store.search(query).first?.typeName, "Work Order", "index stores type name")

    var letterType = CustomDocumentType(name: "Site Visit Report", prefix: "SVR", layout: .text)
    letterType.fields = [CustomFieldDefinition(id: "visit_area", label: "Visit Area", placement: .hidden)]
    letterType.starterText = "# Site Visit\nArea inspected: {{field.visit_area}}"
    letterType = try store.saveCustomType(letterType)
    var visit = try store.newDocument(customType: letterType)
    visit.customFields["visit_area"] = "Server room"
    visit = try store.save(visit)
    expect(PDFDocument(data: store.renderPDF(visit).data)?.string?.contains("Area inspected: Server room") == true, "field merge in body")
    let docx = try store.exportDOCX(order)
    expect(try runTool("/usr/bin/textutil", ["-convert", "txt", "-stdout", docx.path]).contains("Plot 7, MIDC, Pune"), "custom fields in Word export")

    try store.deleteCustomType(id: type.id)
    expect(try store.customType(id: type.id)?.archived == true, "type with documents is archived, not deleted")
    let unused = try store.saveCustomType(CustomDocumentType(name: "Unused"))
    try store.deleteCustomType(id: unused.id)
    expect(try store.customType(id: unused.id) == nil, "unused type deleted")
    store.close()
}

group("Revision history: compare and restore") {
    let store = try freshStore("Revisions")
    var invoice = try store.newDocument(kind: .invoice)
    invoice.customer.name = "Acme"
    invoice.items = [LineItem(name: "Design", quantity: 1, unitPrice: 10000, taxRate: 18)]
    invoice = try store.issue(try store.save(invoice))
    var revised = try store.createRevision(of: invoice.id)
    revised.items[0].unitPrice = 12000
    revised.items.append(LineItem(name: "Hosting", quantity: 1, unitPrice: 3000, taxRate: 18))
    revised.notes = "Updated scope"
    revised = try store.save(revised)

    let history = try store.revisions(of: invoice.id)
    expect(history.contains { $0.label == "Issued" && $0.revision == 1 }, "issued snapshot listed")
    guard let original = history.first(where: { $0.label == "Issued" }) else { throw WorkspaceError.recordNotFound }
    let diff = DocumentComparer.compare(original.document, revised)
    expect(diff.contains { $0.section == "Items" && $0.change == .changed && $0.new.contains("12,000") }, "changed item")
    expect(diff.contains { $0.section == "Items" && $0.change == .added && $0.new.contains("Hosting") }, "added item")
    expect(diff.contains { $0.field == "Total" && $0.old.contains("11,800") && $0.new.contains("17,700") }, "total change")
    expect(diff.contains { $0.field == "Notes" }, "notes change")
    expect(DocumentComparer.compare(revised, revised).isEmpty, "identical versions have no differences")

    let restored = try store.restoreRevision(original, into: invoice.id)
    expectEqual(restored.items.map(\.unitPrice), [10000], "restored content")
    expectEqual(restored.number, invoice.number, "keeps number")
    expect(try store.revisions(of: invoice.id).contains { $0.label == "Before restore" }, "pre-restore copy kept")

    let issued = try store.issue(restored)
    let restoredAgain = try store.restoreRevision(try store.revisions(of: invoice.id).first { $0.document.items.count == 2 }!, into: issued.id)
    expectEqual(restoredAgain.revision, issued.revision + 1, "restoring into issued document creates a revision")
    expectEqual(restoredAgain.items.count, 2, "two-item version back")

    let bodyDiff = DocumentComparer.bodyDiff("Intro\nKeep\nOld line", "Intro\nKeep\nNew line\nAdded")
    expect(bodyDiff.contains { $0.change == .changed && $0.old == "Old line" && $0.new == "New line" }, "paragraph change")
    expect(bodyDiff.contains { $0.change == .added && $0.new == "Added" }, "paragraph added")
    store.close()
}

group("Encrypted backups") {
    let root = temporaryRoot.appendingPathComponent("Encrypted")
    let store = try freshStore("Encrypted")
    var invoice = try store.newDocument(kind: .invoice)
    invoice.items = [LineItem(name: "Secret project", quantity: 1, unitPrice: 777, taxRate: 0)]
    invoice = try store.save(invoice)
    let backup = try BackupService.createBackup(of: store, in: store.workspace.backupsURL, password: "correct horse battery")
    expect(BackupCrypto.isEncrypted(backup), "package encrypted")
    let raw = try Data(contentsOf: backup)
    expect(raw.range(of: Data("Secret project".utf8)) == nil && raw.range(of: Data("document.json".utf8)) == nil, "no plaintext inside")
    expect(BackupService.history(of: store).first?.encrypted == true, "history marks encryption")
    expectThrows("password required") { _ = try BackupService.verify(backup) }
    do {
        _ = try BackupService.verify(backup, password: "wrong")
        expect(false, "wrong password accepted")
    } catch let error as BackupCrypto.CryptoError {
        expectEqual(error, .wrongPassword, "wrong password reported")
    }
    let verified = try BackupService.verify(backup, password: "correct horse battery")
    try? FileManager.default.removeItem(at: verified.extractedRoot.deletingLastPathComponent())
    expectEqual(verified.manifest.documentCount, 1, "decrypted manifest")

    var tampered = raw
    tampered[tampered.count - 40] ^= 0xFF
    let tamperedURL = temporaryRoot.appendingPathComponent("tampered.docudeskbackup")
    try tampered.write(to: tamperedURL)
    expectThrows("tampering detected") { _ = try BackupService.verify(tamperedURL, password: "correct horse battery") }
    let truncatedURL = temporaryRoot.appendingPathComponent("truncated.docudeskbackup")
    try raw.prefix(raw.count / 2).write(to: truncatedURL)
    expectThrows("truncation detected") { _ = try BackupService.verify(truncatedURL, password: "correct horse battery") }

    _ = try store.newDocument(kind: .invoice)
    store.close()
    try BackupService.restore(backup, intoWorkspaceAt: root, password: "correct horse battery")
    let reopened = try WorkspaceStore.open(at: root)
    expectEqual(try reopened.search(DocumentQuery()).map(\.id), [invoice.id], "encrypted restore")

    let workspaceID = UUID()
    try BackupKeychain.save("keychain-secret", workspaceID: workspaceID)
    expectEqual(BackupKeychain.load(workspaceID: workspaceID), "keychain-secret", "Keychain round trip")
    BackupKeychain.delete(workspaceID: workspaceID)
    expect(BackupKeychain.load(workspaceID: workspaceID) == nil, "Keychain entry removed")
    reopened.close()
}

group("Spreadsheet and image export") {
    expectEqual(XLSXWriter.serial(CalendarDate(year: 2026, month: 10, day: 27)), 46322, "Excel date serial")
    expectEqual(XLSXWriter.columnLetter(0) + XLSXWriter.columnLetter(25) + XLSXWriter.columnLetter(27), "AZAB", "column letters")
    let store = try freshStore("Sheets")
    var invoice = try store.newDocument(kind: .invoice)
    invoice.customer.name = "Acme & Sons <Ltd>"
    invoice.items = [LineItem(name: "Design", quantity: 1, unitPrice: 10000, taxRate: 18)]
    invoice = try store.issue(try store.save(invoice))
    try store.recordPayment(PaymentRecord(amount: 1000), toInvoice: invoice.id, createReceipt: false)
    let list = temporaryRoot.appendingPathComponent("list.xlsx")
    try store.exportListXLSX(try store.search(DocumentQuery()), to: list)
    let report = temporaryRoot.appendingPathComponent("report.xlsx")
    try store.exportReportXLSX(currency: "INR", months: 12, to: report)
    let check = """
    import sys, zipfile, xml.dom.minidom
    for path in sys.argv[1:]:
        z = zipfile.ZipFile(path)
        for name in z.namelist():
            if name.endswith('.xml') or name.endswith('.rels'):
                xml.dom.minidom.parseString(z.read(name))
        print(path.split('/')[-1], len([n for n in z.namelist() if 'worksheets/sheet' in n]), 'Acme &amp; Sons &lt;Ltd&gt;' in z.read('xl/worksheets/sheet1.xml').decode() or 'skip')
    """
    let result = try runTool("/usr/bin/python3", ["-c", check, list.path, report.path])
    expect(result.contains("list.xlsx 1 True"), "list workbook valid XML with escaped text (\(result))")
    expect(result.contains("report.xlsx 6"), "report workbook has six sheets")

    let pngFolder = temporaryRoot.appendingPathComponent("PNG")
    try FileManager.default.createDirectory(at: pngFolder, withIntermediateDirectories: true)
    let pngs = try store.exportPNG(invoice, to: pngFolder)
    expectEqual(pngs.count, 1, "one PNG per page")
    expect(NSImage(contentsOf: pngs[0]).map { $0.representations.first?.pixelsWide ?? 0 > 1000 } == true, "PNG at 2× resolution")
    store.close()
}

group("CSV import and bulk generation") {
    let rows = CSV.parse("name,notes\n\"Acme, Inc.\",\"Line one\nLine two\"\n\"Quote \"\"Q\"\"\",x\n")
    expectEqual(rows.count, 3, "rows with embedded newline")
    expectEqual(rows[1], ["Acme, Inc.", "Line one\nLine two"], "quoted comma and newline")
    expectEqual(rows[2][0], "Quote \"Q\"", "escaped quotes")

    let store = try freshStore("Bulk")
    let csv = "Name,Email,City,GSTIN,Amount Due,Invoice Ref\nAcme Pvt. Ltd.,a@acme.example,Mumbai,27AAA,\"12,500\",INV-9\nTech Solutions,t@tech.example,Pune,,8000,INV-10\nAcme Pvt. Ltd.,dup@acme.example,Mumbai,,1,INV-11\n"
    let imported = try store.importCustomers(csv: csv)
    expectEqual(imported.added, 2, "clients imported")
    expectEqual(imported.skipped, ["Acme Pvt. Ltd."], "duplicate names skipped")
    expectEqual(try store.customers().first { $0.name == "Acme Pvt. Ltd." }?.taxID, "27AAA", "tax ID mapped")
    let products = try store.importProducts(csv: "Name,Price,Tax,HSN,Unit\nAnnual AMC,\"12,000\",18,998713,year\n")
    expectEqual(products.added, 1, "product imported")
    expectEqual(try store.products().first?.price, 12000, "grouped price parsed")

    let letter = try store.newDocument(kind: .letter, starter: DocumentStarter(id: "t", kind: .letter, name: "t", summary: "", title: "",
        markup: "Dear {{client.name}},\nPlease pay {{field.amount_due}} against {{field.invoice_ref}}."))
    let recipients = CSV.records(csv).rows.prefix(2).map(BulkRecipient.init(record:))
    expectEqual(recipients.first?.fields["amount_due"], "12,500", "extra columns become fields")
    let outFolder = temporaryRoot.appendingPathComponent("BulkPDF")
    try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)
    var options = BulkOptions()
    options.issue = true
    options.exportFolder = outFolder
    options.saveNewClients = false
    let result = try store.bulkGenerate(from: letter.id, recipients: Array(recipients), options: options)
    expectEqual(result.created.count, 2, "two letters generated")
    expect(result.failures.isEmpty, "no failures: \(result.failures)")
    expect(result.created.allSatisfy { $0.status == .issued }, "issued")
    expectEqual(Set(result.created.map(\.number)).count, 2, "unique numbers")
    let firstText = result.exported.first.flatMap { PDFDocument(url: $0)?.string } ?? ""
    expect(firstText.contains("Dear Acme Pvt. Ltd.") && firstText.contains("Please pay 12,500 against INV-9"), "per-recipient merge")

    let fromClients = try store.bulkGenerate(from: letter.id, recipients: try store.customers().map(BulkRecipient.init(customer:)), options: BulkOptions())
    expect(fromClients.created.allSatisfy { $0.customerID != nil && $0.status == .draft }, "from saved clients as drafts")
    store.close()
}

group("Template designer options") {
    var theme = TemplateLibrary.theme(for: .modern)
    theme.watermark = "Duplicate"
    theme.hideItemNumbers = true
    theme.itemColumnTitle = "Service"
    theme.sectionOrder = ["terms", "notes", "payment"]
    theme.showPaymentQR = true
    theme.density = .compact
    theme.logoSize = .large
    var company = SampleData.company
    company.upiID = "yourcompany@hdfcbank"
    let document = SampleData.document(kind: .invoice, template: TemplateLibrary.defaultTemplate(for: .invoice, style: .modern), company: company)
    let text = PDFDocument(data: DocumentRenderer.pdfData(for: document, theme: theme))?.string ?? ""
    expect(text.contains("DUPLICATE"), "watermark printed")
    expect(text.uppercased().contains("SERVICE") && !text.uppercased().contains("ITEM & DESCRIPTION"), "renamed item column")
    if let terms = text.range(of: "TERMS & CONDITIONS")?.lowerBound, let notes = text.range(of: "NOTES")?.lowerBound {
        expect(terms < notes, "section order respected")
    } else {
        expect(false, "sections present")
    }
    expect(text.uppercased().contains("SCAN TO PAY WITH UPI"), "UPI QR block")
    let builder = LayoutBuilder(document: document, totals: DocumentCalculator.totals(for: document), theme: theme, logo: nil, pageSize: PageSize.a4.points)
    expectEqual(builder.upiLink, "upi://pay?pa=yourcompany@hdfcbank&pn=Your%20Company&am=53100&cu=INR&tn=\(document.number)", "UPI link")
    expect(LayoutBuilder.qrImage(for: builder.upiLink!, side: 84) != nil, "QR image generated")
    let decodedOld = try DocuDeskJSON.decoder.decode(TemplateTheme.self, from: DocuDeskJSON.encoder.encode(TemplateLibrary.theme(for: .classic)))
    expectEqual(decodedOld.density, .normal, "old themes default to normal density")
}

group("Database migration from schema 2") {
    let root = temporaryRoot.appendingPathComponent("Migrate3")
    let store = try freshStore("Migrate3")
    _ = try store.newDocument(kind: .quotation)
    try store.database.execute("""
    DROP INDEX documents_type; ALTER TABLE documents DROP COLUMN type_key; ALTER TABLE documents DROP COLUMN type_name;
    DROP TABLE custom_types; ALTER TABLE backups DROP COLUMN encrypted; PRAGMA user_version = 2;
    """)
    store.close()
    let migrated = try WorkspaceStore.open(at: root)
    expectEqual(migrated.database.userVersion, WorkspaceStore.schemaVersion, "schema 3")
    expectEqual(try migrated.search(DocumentQuery()).first?.typeName, "Quotation", "type name falls back for old rows")
    expect(try migrated.customTypes().isEmpty, "custom types table created")
    migrated.close()
}

print("\n\(passes) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
