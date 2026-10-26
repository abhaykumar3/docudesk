import AppKit
import Foundation
import PDFKit

extension WorkspaceStore {
    /// One PNG per page at 2× resolution, named `<number>-p1.png`, `<number>-p2.png`, …
    @discardableResult
    public func exportPNG(_ document: DocumentRecord, to directory: URL, scale: CGFloat = 2) throws -> [URL] {
        guard let pdf = PDFDocument(data: renderPDF(document).data) else { return [] }
        var urls: [URL] = []
        let base = (pdfFileName(for: document) as NSString).deletingPathExtension
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            let name = pdf.pageCount == 1 ? "\(base).png" : "\(base)-p\(index + 1).png"
            let url = Self.uniqueURL(in: directory, name: name)
            do {
                try png.write(to: url, options: .atomic)
            } catch {
                throw WorkspaceError.notWritable(url.path)
            }
            urls.append(url)
        }
        return urls
    }

    /// A document list as a spreadsheet.
    public func exportListXLSX(_ documents: [DocumentSummary], to url: URL) throws {
        let sheet = XLSXWriter.Sheet(
            name: "Documents",
            columns: [
                .init("Number", width: 18), .init("Type", width: 18), .init("Client", width: 28), .init("Date", width: 13),
                .init("Due", width: 13), .init("Currency", width: 10), .init("Total", width: 14), .init("Balance", width: 14),
                .init("Status", width: 15), .init("Tags", width: 22),
            ],
            rows: documents.map { document in
                [
                    .text(document.number), .text(document.typeName), .text(document.customerName), .date(document.issueDate),
                    document.dueDate.map { .date($0) } ?? .empty, .text(document.currency),
                    document.kind.showsPricing || document.kind == .custom ? .money(document.total) : .empty,
                    document.kind.showsPricing ? .money(document.balance) : .empty,
                    .text(document.effectiveStatus.displayName), .text(document.tags.joined(separator: ", ")),
                ]
            }
        )
        try XLSXWriter.write([sheet], to: url)
    }

    /// Business report workbook: summary, monthly totals, top clients, invoices, payments and items.
    public func exportReportXLSX(currency: String, months: Int, to url: URL) throws {
        let stats = try dashboardStats()
        func amount(_ values: [CurrencyAmount]) -> XLSXWriter.Cell {
            .money(values.first { $0.currency == currency }?.amount ?? 0)
        }
        let summary = XLSXWriter.Sheet(
            name: "Summary",
            columns: [.init("Measure", width: 28), .init("Value (\(currency))", width: 18)],
            rows: [
                [.text("Invoiced"), amount(stats.invoiced)],
                [.text("Paid"), amount(stats.paid)],
                [.text("Outstanding"), amount(stats.outstanding)],
                [.text("Overdue"), amount(stats.overdue)],
                [.text("Overdue invoices"), .number(Decimal(stats.overdueCount))],
                [.text("Documents"), .number(Decimal(stats.total))],
                [.text("Generated"), .date(.today)],
            ]
        )
        let monthly = XLSXWriter.Sheet(
            name: "Monthly",
            columns: [.init("Month", width: 14), .init("Invoices", width: 10), .init("Invoiced", width: 16)],
            rows: try monthlyInvoiced(currency: currency, months: months).map {
                [.date(CalendarDate(year: $0.year, month: $0.month, day: 1)), .number(Decimal($0.count)), .money($0.amount)]
            }
        )
        let clients = XLSXWriter.Sheet(
            name: "Top Clients",
            columns: [.init("Client", width: 30), .init("Invoices", width: 10), .init("Invoiced", width: 16)],
            rows: try topClients(currency: currency, limit: 50).map { [.text($0.name), .number(Decimal($0.count)), .money($0.amount)] }
        )

        var invoiceQuery = DocumentQuery()
        invoiceQuery.kinds = [.invoice]
        invoiceQuery.archive = .all
        let invoices = try search(invoiceQuery).filter { $0.currency == currency }
        var invoiceRows: [[XLSXWriter.Cell]] = []
        var paymentRows: [[XLSXWriter.Cell]] = []
        var itemRows: [[XLSXWriter.Cell]] = []
        for summary in invoices {
            guard let invoice = try? loadDocument(id: summary.id) else { continue }
            let totals = DocumentCalculator.totals(for: invoice)
            invoiceRows.append([
                .text(invoice.number), .text(invoice.customer.name), .date(invoice.issueDate), invoice.dueDate.map { .date($0) } ?? .empty,
                .money(totals.taxableAmount), .money(totals.taxTotal), .money(totals.grandTotal), .money(totals.amountPaid + totals.advancePaid),
                .money(summary.balance), .text(summary.effectiveStatus.displayName),
            ])
            for payment in invoice.payments {
                paymentRows.append([.text(invoice.number), .text(invoice.customer.name), .date(payment.date), .text(payment.method.displayName),
                                    .text(payment.reference), .money(payment.amount), .text(payment.receiptNumber ?? "")])
            }
            for item in invoice.items {
                let line = totals.line(for: item.id)
                itemRows.append([.text(invoice.number), .date(invoice.issueDate), .text(item.name), .text(item.hsnSac), .number(item.quantity),
                                 .text(item.unit), .money(item.unitPrice), .number(item.taxRate), .money(line?.net ?? 0)])
            }
        }
        let invoiceSheet = XLSXWriter.Sheet(
            name: "Invoices",
            columns: [.init("Number", width: 18), .init("Client", width: 28), .init("Date", width: 13), .init("Due", width: 13),
                      .init("Taxable", width: 14), .init("Tax", width: 12), .init("Total", width: 14), .init("Paid", width: 14),
                      .init("Balance", width: 14), .init("Status", width: 15)],
            rows: invoiceRows
        )
        let paymentSheet = XLSXWriter.Sheet(
            name: "Payments",
            columns: [.init("Invoice", width: 18), .init("Client", width: 28), .init("Date", width: 13), .init("Method", width: 14),
                      .init("Reference", width: 20), .init("Amount", width: 14), .init("Receipt", width: 16)],
            rows: paymentRows
        )
        let itemSheet = XLSXWriter.Sheet(
            name: "Invoice Items",
            columns: [.init("Invoice", width: 18), .init("Date", width: 13), .init("Item", width: 32), .init("HSN/SAC", width: 10),
                      .init("Qty", width: 8), .init("Unit", width: 8), .init("Rate", width: 12), .init("Tax %", width: 8), .init("Amount", width: 14)],
            rows: itemRows
        )
        try XLSXWriter.write([summary, monthly, clients, invoiceSheet, paymentSheet, itemSheet], to: url)
    }
}
