import AppKit
import Foundation

/// Writes an editable Word (.docx) version of a document by generating Office Open XML directly.
/// PDF stays the reference output; DOCX keeps the same content and structure in editable form.
public enum DocxExporter {
    public enum ExportError: LocalizedError {
        case zipFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .zipFailed(message): "The Word file couldn’t be packaged: \(message)"
            }
        }
    }

    public static func export(_ document: DocumentRecord, theme: TemplateTheme, logo: NSImage?, to url: URL) throws {
        let writer = DocxWriter(document: document, theme: theme)
        writer.build(logo: logo)
        try writer.package(to: url)
    }
}

final class DocxWriter {
    let document: DocumentRecord
    let theme: TemplateTheme
    let totals: DocumentTotals
    private var body = ""
    private var media: [(name: String, data: Data)] = []
    private var imageRelationships: [(id: String, target: String)] = []
    private var drawingID = 1

    let bodyFamily: String
    let headingFamily: String
    let accentHex: String
    let mutedHex: String

    /// Printable width in twentieths of a point.
    let contentWidth: Int
    let pageWidth: Int
    let pageHeight: Int
    let margin = 1134

    init(document: DocumentRecord, theme: TemplateTheme) {
        self.document = document
        self.theme = theme
        totals = DocumentCalculator.totals(for: document)
        bodyFamily = NSFont(name: theme.bodyFont, size: 10)?.familyName ?? "Helvetica"
        headingFamily = NSFont(name: theme.headingFont, size: 10)?.familyName ?? bodyFamily
        accentHex = String(theme.accent.hexString.dropFirst())
        mutedHex = String(theme.muted.hexString.dropFirst())
        var size = document.pageSize.points
        if document.orientation == .landscape { size = CGSize(width: size.height, height: size.width) }
        pageWidth = Int(size.width * 20)
        pageHeight = Int(size.height * 20)
        contentWidth = pageWidth - 2 * 1134
    }

    // MARK: XML helpers

    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default:
                // Drop control characters XML can't carry (tabs, breaks and form feeds are handled by the caller).
                if let scalar = character.unicodeScalars.first, scalar.value < 0x20 { continue }
                result.append(character)
            }
        }
        return result
    }

    struct RunStyle {
        var bold = false
        var italic = false
        var underline = false
        var size: CGFloat = 10.5
        var color: String?
        var font: String?
    }

    func run(_ text: String, _ style: RunStyle) -> String {
        var properties = ""
        let font = style.font ?? bodyFamily
        properties += "<w:rFonts w:ascii=\"\(Self.escape(font))\" w:hAnsi=\"\(Self.escape(font))\" w:cs=\"\(Self.escape(font))\"/>"
        if style.bold { properties += "<w:b/>" }
        if style.italic { properties += "<w:i/>" }
        if style.underline { properties += "<w:u w:val=\"single\"/>" }
        if let color = style.color { properties += "<w:color w:val=\"\(color)\"/>" }
        properties += "<w:sz w:val=\"\(Int((style.size * 2).rounded()))\"/>"

        var content = ""
        var buffer = ""
        func flush() {
            if !buffer.isEmpty {
                content += "<w:t xml:space=\"preserve\">\(Self.escape(buffer))</w:t>"
                buffer = ""
            }
        }
        for character in text {
            switch character {
            case "\t": flush(); content += "<w:tab/>"
            case "\u{2028}", "\n", "\r": flush(); content += "<w:br/>"
            case "\u{000C}": flush(); content += "<w:br w:type=\"page\"/>"
            default: buffer.append(character)
            }
        }
        flush()
        return "<w:r><w:rPr>\(properties)</w:rPr>\(content)</w:r>"
    }

    func paragraph(_ runs: String, align: String? = nil, spacingAfter: Int = 100, style: String? = nil, indentLeft: Int? = nil, hanging: Int? = nil) -> String {
        var properties = ""
        if let style { properties += "<w:pStyle w:val=\"\(style)\"/>" }
        properties += "<w:spacing w:after=\"\(spacingAfter)\"/>"
        if let indentLeft { properties += "<w:ind w:left=\"\(indentLeft)\"\(hanging.map { " w:hanging=\"\($0)\"" } ?? "")/>" }
        if let align { properties += "<w:jc w:val=\"\(align)\"/>" }
        return "<w:p><w:pPr>\(properties)</w:pPr>\(runs)</w:p>"
    }

    func text(_ value: String, size: CGFloat = 10.5, bold: Bool = false, color: String? = nil, font: String? = nil, align: String? = nil, after: Int = 100) -> String {
        paragraph(run(value, RunStyle(bold: bold, size: size, color: color, font: font)), align: align, spacingAfter: after)
    }

    func label(_ value: String) -> String {
        text(value.uppercased(), size: 8, bold: true, color: accentHex, after: 40)
    }

    /// A borderless or bordered table from rows of pre-built cell XML.
    func table(widths: [Int], rows: [[String]], header: Bool, borders: Bool = true, shadeHeader: Bool = true) -> String {
        let border = borders ? "single" : "nil"
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"\(widths.reduce(0, +))\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblBorders>"
        for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
            xml += "<w:\(edge) w:val=\"\(border)\" w:sz=\"4\" w:space=\"0\" w:color=\"C8C8C8\"/>"
        }
        xml += "</w:tblBorders><w:tblCellMar><w:top w:w=\"60\" w:type=\"dxa\"/><w:left w:w=\"100\" w:type=\"dxa\"/><w:bottom w:w=\"60\" w:type=\"dxa\"/><w:right w:w=\"100\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>"
        for width in widths { xml += "<w:gridCol w:w=\"\(width)\"/>" }
        xml += "</w:tblGrid>"
        for (index, row) in rows.enumerated() {
            // The header row repeats on every page Word breaks the table across.
            xml += index == 0 && header ? "<w:tr><w:trPr><w:tblHeader/></w:trPr>" : "<w:tr>"
            for (column, cell) in row.enumerated() where column < widths.count {
                let shade = index == 0 && header && shadeHeader ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(String(theme.tint.hexString.dropFirst()))\"/>" : ""
                let content = cell.isEmpty ? "<w:p/>" : cell
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(widths[column])\" w:type=\"dxa\"/>\(shade)</w:tcPr>\(content)</w:tc>"
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>" + "<w:p><w:pPr><w:spacing w:after=\"120\"/></w:pPr></w:p>"
    }

    // MARK: Images

    func image(_ image: NSImage, maxWidthPoints: CGFloat) -> String {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]), image.size.width > 0 else { return "" }
        let index = media.count + 1
        let name = "image\(index).png"
        media.append((name, png))
        let relationship = "rIdImg\(index)"
        imageRelationships.append((relationship, "media/\(name)"))
        let scale = min(1, maxWidthPoints / image.size.width)
        let cx = Int(image.size.width * scale * 12700)
        let cy = Int(image.size.height * scale * 12700)
        let id = drawingID
        drawingID += 1
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(id)" name="Picture \(id)"/>\
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(id)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(relationship)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>\
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    // MARK: Content

    func build(logo: NSImage?) {
        header(logo: logo)
        parties()
        if document.kind == .receipt {
            receipt()
        } else {
            if document.usesBody { richBody() }
            if document.usesLineItems, !(document.usesBody && document.items.isEmpty) {
                items()
                if document.showsPricing { totalsBlock() }
            }
        }
        notes()
        if !theme.hideSignature { signature() }
    }

    private var title: String {
        if document.usesBody { return "" }
        var title = document.printedTitle
        if document.kind == .invoice, [.cgstSgst, .igst].contains(document.taxSplit) { title = "Tax Invoice" }
        return theme.uppercaseTitle ? title.uppercased() : title
    }

    private func header(logo: NSImage?) {
        let company = document.company
        var left = ""
        if let logo { left += paragraph(image(logo, maxWidthPoints: 140), spacingAfter: 80) }
        left += text(company.displayLegalName, size: 16, bold: true, font: headingFamily, after: 40)
        var lines = company.address.lines
        if !company.taxID.isEmpty { lines.append("\(company.taxIDLabel): \(company.taxID)") }
        let contact = [company.phone, company.email].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !contact.isEmpty { lines.append(contact) }
        if !company.website.isEmpty { lines.append(company.website) }
        for line in lines { left += text(line, size: 8.5, color: mutedHex, after: 0) }

        var right = ""
        if !title.isEmpty { right += text(title, size: 22, bold: true, color: accentHex, font: headingFamily, align: "right", after: 40) }
        right += text(document.number, size: 9.5, color: mutedHex, align: "right", after: 0)
        let half = contentWidth / 2
        body += table(widths: [half + 600, half - 600], rows: [[left, right]], header: false, borders: false)
    }

    private func parties() {
        let customer = document.customer
        var lines = customer.billingAddress.lines
        if !customer.contactPerson.isEmpty { lines.insert("Attn: \(customer.contactPerson)", at: 0) }
        if !customer.taxID.isEmpty { lines.append("\(document.company.taxIDLabel): \(customer.taxID)") }
        let contact = [customer.phone, customer.email].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !contact.isEmpty { lines.append(contact) }
        var party = label(document.partyLabel) + text(customer.name.isEmpty ? "—" : customer.name, size: 11, bold: true, after: 20)
        for line in lines { party += text(line, size: 9, color: mutedHex, after: 0) }

        var meta: [(String, String)] = [(document.numberLabel, document.number), ("Date", document.issueDate.display)]
        if let due = document.dueDate, let dueLabel = document.dueDateLabel { meta.append((dueLabel, due.display)) }
        if !document.reference.isEmpty { meta.append(("Reference", document.reference)) }
        if !document.placeOfSupply.isEmpty { meta.append(("Place of Supply", document.placeOfSupply)) }
        if document.revision > 1 { meta.append(("Revision", "R\(document.revision)")) }
        meta += document.customFieldRows(.meta)
        let metaXML = meta.map { name, value in
            paragraph(run(name + ":  ", RunStyle(size: 9, color: mutedHex)) + run(value, RunStyle(bold: true, size: 9)), align: "right", spacingAfter: 20)
        }.joined()
        let half = contentWidth / 2
        body += table(widths: [half + 600, half - 600], rows: [[party, metaXML]], header: false, borders: false)
        let details = document.customFieldRows(.details)
        if !details.isEmpty {
            body += label("Details")
            body += table(widths: [contentWidth / 3, contentWidth - contentWidth / 3],
                          rows: details.map { [text($0.0, size: 9, color: mutedHex, after: 0), text($0.1, size: 9.5, bold: true, after: 0)] },
                          header: false, borders: true, shadeHeader: false)
        }
    }

    private func items() {
        let pricing = document.showsPricing
        let currency = document.currency
        var widths = [500, 0, 1100]
        var headers = ["#", "Item & Description", "Qty"]
        if pricing {
            widths += [1500, 1700]
            headers += ["Rate", "Amount"]
        }
        widths[1] = contentWidth - widths.reduce(0, +)
        var rows: [[String]] = [headers.enumerated().map { index, title in
            text(title.uppercased(), size: 8, bold: true, align: index >= 2 ? "right" : nil, after: 0)
        }]
        for (index, item) in document.items.enumerated() {
            let line = totals.line(for: item.id)
            var description = text(item.name.isEmpty ? "Item" : item.name, size: 9.5, bold: true, after: 0)
            if !item.details.isEmpty { description += text(item.details, size: 8.5, color: mutedHex, after: 0) }
            if !item.hsnSac.isEmpty, !theme.hideHSN { description += text("HSN/SAC: \(item.hsnSac)", size: 8, color: mutedHex, after: 0) }
            var row = [
                text("\(index + 1)", size: 9, after: 0),
                description,
                text(MoneyFormatter.quantity(item.quantity) + (item.unit.isEmpty ? "" : " \(item.unit)"), size: 9, align: "right", after: 0),
            ]
            if pricing {
                row.append(text(MoneyFormatter.number(item.unitPrice, currency: currency), size: 9, align: "right", after: 0))
                row.append(text(MoneyFormatter.number(line?.net ?? 0, currency: currency), size: 9, bold: true, align: "right", after: 0))
            }
            rows.append(row)
        }
        body += table(widths: widths, rows: rows, header: true)
    }

    private func totalsBlock() {
        let currency = document.currency
        var rows: [(String, String, Bool)] = [("Subtotal", MoneyFormatter.number(totals.subtotal, currency: currency), false)]
        if totals.documentDiscount > 0 { rows.append(("Discount", "−" + MoneyFormatter.number(totals.documentDiscount, currency: currency), false)) }
        if !totals.taxLines.isEmpty, totals.taxableAmount != totals.subtotal { rows.append(("Taxable value", MoneyFormatter.number(totals.taxableAmount, currency: currency), false)) }
        for tax in totals.taxLines { rows.append((tax.label, MoneyFormatter.number(tax.amount, currency: currency), false)) }
        if totals.shipping != 0 { rows.append(("Shipping", MoneyFormatter.number(totals.shipping, currency: currency), false)) }
        if totals.adjustment != 0 { rows.append((document.adjustmentLabel, MoneyFormatter.number(totals.adjustment, currency: currency), false)) }
        if totals.roundOff != 0 { rows.append(("Round off", MoneyFormatter.number(totals.roundOff, currency: currency), false)) }
        rows.append(("Total", MoneyFormatter.format(totals.grandTotal, currency: currency), true))
        if totals.advancePaid > 0 { rows.append(("Advance received", "−" + MoneyFormatter.number(totals.advancePaid, currency: currency), false)) }
        if totals.amountPaid > 0 { rows.append(("Amount paid", "−" + MoneyFormatter.number(totals.amountPaid, currency: currency), false)) }
        if totals.advancePaid > 0 || totals.amountPaid > 0 { rows.append(("Balance due", MoneyFormatter.format(totals.balanceDue, currency: currency), true)) }

        let tableRows = rows.map { title, value, strong in
            [text(title, size: strong ? 10.5 : 9, bold: strong, color: strong ? nil : mutedHex, after: 0),
             text(value, size: strong ? 11 : 9.5, bold: strong, color: strong ? accentHex : nil, align: "right", after: 0)]
        }
        let words = theme.hideAmountInWords ? "<w:p/>" : label("Amount in words") + text(totals.amountInWords, size: 9.5, bold: true, after: 0)
        let blockWidth = 4200
        let totalsTable = table(widths: [2400, blockWidth - 2400], rows: tableRows, header: false, borders: false)
        body += table(widths: [contentWidth - blockWidth, blockWidth], rows: [[words, totalsTable]], header: false, borders: false)
    }

    private func receipt() {
        guard let receipt = document.receipt else { return }
        body += label("Amount received")
        body += text(MoneyFormatter.format(totals.grandTotal, currency: document.currency), size: 22, bold: true, color: accentHex, font: headingFamily, after: 160)
        var sentence = "Received with thanks from \(document.customer.name.isEmpty ? "—" : document.customer.name) the sum of \(totals.amountInWords) by \(receipt.method.displayName.lowercased())"
        if !receipt.againstDocumentNumber.isEmpty { sentence += " towards invoice \(receipt.againstDocumentNumber)" }
        if !receipt.purpose.isEmpty { sentence += " for \(receipt.purpose)" }
        body += text(sentence + ".", size: 10.5, after: 120)
        if !receipt.transactionReference.isEmpty { body += text("Transaction reference: \(receipt.transactionReference)", size: 9.5, color: mutedHex) }
    }

    private func notes() {
        for (title, content) in [("Payment details", document.paymentDetails), ("Notes", document.notes), ("Terms & conditions", document.terms)]
            where !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += label(title)
            for line in content.components(separatedBy: "\n") { body += text(line, size: 9, after: 20) }
            body += paragraph("", spacingAfter: 120)
        }
    }

    private func signature() {
        let name = document.company.signatoryName.trimmingCharacters(in: .whitespaces)
        func block(_ heading: String, _ caption: String) -> String {
            text(heading, size: 9.5, bold: true, align: "center", after: 600)
                + text("______________________", size: 9, color: mutedHex, align: "center", after: 20)
                + text(caption, size: 8.5, color: mutedHex, align: "center", after: 0)
                + (document.kind == .agreement ? text("Date: ____________", size: 8.5, color: mutedHex, align: "center", after: 0) : "")
        }
        let companyBlock = block("For \(document.company.displayLegalName)", name.isEmpty ? "Authorised Signatory" : "\(name), Authorised Signatory")
        var clientBlock = "<w:p/>"
        if document.kind == .agreement {
            let client = document.customer.name.isEmpty ? "the Client" : document.customer.name
            clientBlock = block("For \(client)", document.customer.contactPerson.isEmpty ? "Authorised Signatory" : "\(document.customer.contactPerson), Authorised Signatory")
        }
        let half = contentWidth / 2
        body += table(widths: [half, half], rows: [[clientBlock, companyBlock]], header: false, borders: false)
    }

    // MARK: Rich text

    private func richBody() {
        let merged = RichTextTransform.preparedForPrint(MergeFields.apply(to: document.body.attributedString(), document: document))
        let string = merged.string as NSString
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = merged.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            if let block = style?.textBlocks.first as? NSTextTableBlock {
                location = richTable(merged, startingAt: range.location, table: block.table)
                continue
            }
            body += richParagraph(merged, range: range, style: style)
            location = NSMaxRange(range)
        }
    }

    private func contentRange(_ range: NSRange, in string: NSString) -> NSRange {
        var content = range
        while content.length > 0 {
            let last = string.character(at: NSMaxRange(content) - 1)
            guard last == 0x0A || last == 0x0D || last == 0x2029 else { break }
            content.length -= 1
        }
        return content
    }

    private func richRuns(_ text: NSAttributedString, range: NSRange) -> String {
        var runs = ""
        text.enumerateAttributes(in: range) { attributes, runRange, _ in
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                if let picture = RichTextTransform.image(of: attachment) {
                    runs += image(picture, maxWidthPoints: CGFloat(contentWidth) / 20)
                }
                return
            }
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            var style = RunStyle()
            style.size = font?.pointSize ?? 10.5
            style.bold = traits.contains(.bold) || (font?.fontName.lowercased().contains("bold") ?? false)
                || (font?.fontName.lowercased().contains("semibold") ?? false) || (font?.fontName.lowercased().contains("demibold") ?? false)
            style.italic = traits.contains(.italic)
            style.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
            style.font = font?.familyName
            if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB), color.brightnessComponent > 0.05 || color.saturationComponent > 0.05 {
                style.color = RGBColor(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent)).hexString.replacingOccurrences(of: "#", with: "")
            }
            runs += run((text.string as NSString).substring(with: runRange), style)
        }
        return runs
    }

    private func richParagraph(_ text: NSAttributedString, range: NSRange, style: NSParagraphStyle?) -> String {
        let content = contentRange(range, in: text.string as NSString)
        guard content.length > 0 else { return paragraph("", spacingAfter: 60) }
        var align: String?
        switch style?.alignment {
        case .center: align = "center"
        case .right: align = "right"
        case .justified: align = "both"
        default: align = nil
        }
        let isList = !(style?.textLists.isEmpty ?? true)
        var listRange = content
        if isList, (text.string as NSString).character(at: content.location) == 0x09 {
            // Drop the leading tab before the list marker; Word handles indentation instead.
            listRange = NSRange(location: content.location + 1, length: content.length - 1)
        }
        let after = Int((style?.paragraphSpacing ?? 6) * 20)
        return paragraph(richRuns(text, range: listRange), align: align, spacingAfter: after,
                         indentLeft: isList ? 480 : nil, hanging: isList ? 360 : nil)
    }

    /// Converts consecutive paragraphs belonging to one NSTextTable into a Word table.
    private func richTable(_ text: NSAttributedString, startingAt start: Int, table: NSTextTable) -> Int {
        let string = text.string as NSString
        var cells: [Int: [Int: String]] = [:]
        var location = start
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            guard let block = style?.textBlocks.first as? NSTextTableBlock, block.table === table else { break }
            let content = contentRange(range, in: string)
            let xml = paragraph(richRuns(text, range: content), spacingAfter: 0)
            cells[block.startingRow, default: [:]][block.startingColumn, default: ""] += xml
            location = NSMaxRange(range)
        }
        let columns = max(table.numberOfColumns, 1)
        let width = contentWidth / columns
        let rows = cells.keys.sorted().map { row in (0..<columns).map { cells[row]?[$0] ?? "" } }
        body += self.table(widths: Array(repeating: width, count: columns), rows: rows, header: true)
        return location
    }

    // MARK: Packaging

    func package(to url: URL) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("DocuDesk-Docx-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        for folder in ["_rels", "docProps", "word/_rels", "word/media"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        func write(_ path: String, _ text: String) throws {
            try Data(text.utf8).write(to: root.appendingPathComponent(path))
        }
        try write("[Content_Types].xml", contentTypes)
        try write("_rels/.rels", packageRelationships)
        try write("docProps/core.xml", coreProperties)
        try write("word/document.xml", documentXML)
        try write("word/styles.xml", stylesXML)
        try write("word/footer1.xml", footerXML)
        try write("word/_rels/document.xml.rels", documentRelationships)
        for item in media {
            try item.data.write(to: root.appendingPathComponent("word/media/\(item.name)"))
        }

        try Packager.zip(directory: root, to: url)
    }

    private var contentTypes: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Default Extension="png" ContentType="image/png"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>\
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
        </Types>
        """
    }

    private var packageRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
        </Relationships>
        """
    }

    private var coreProperties: String {
        let title = document.usesBody && !document.title.isEmpty ? document.title : "\(document.typeName) \(document.number)"
        let created = ISO8601DateFormatter().string(from: document.createdAt)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(Self.escape(title))</dc:title><dc:creator>\(Self.escape(document.company.name))</dc:creator>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(created)</dcterms:created></cp:coreProperties>
        """
    }

    private var documentRelationships: String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
        """
        for item in imageRelationships {
            xml += "<Relationship Id=\"\(item.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(item.target)\"/>"
        }
        return xml + "</Relationships>"
    }

    private var documentXML: String {
        let orientation = document.orientation == .landscape ? " w:orient=\"landscape\"" : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>\(body)\
        <w:sectPr><w:footerReference w:type="default" r:id="rIdFooter"/><w:pgSz w:w="\(pageWidth)" w:h="\(pageHeight)"\(orientation)/>\
        <w:pgMar w:top="\(margin)" w:right="\(margin)" w:bottom="\(margin)" w:left="\(margin)" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr>\
        </w:body></w:document>
        """
    }

    private var stylesXML: String {
        let body = Self.escape(bodyFamily)
        let heading = Self.escape(headingFamily)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="\(body)" w:hAnsi="\(body)" w:cs="\(body)"/><w:sz w:val="21"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="100" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>\
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>\
        <w:pPr><w:keepNext/><w:spacing w:before="200" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:rFonts w:ascii="\(heading)" w:hAnsi="\(heading)"/><w:b/><w:sz w:val="34"/></w:rPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>\
        <w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:color w:val="\(accentHex)"/><w:sz w:val="24"/></w:rPr></w:style>\
        </w:styles>
        """
    }

    private var footerXML: String {
        let company = Self.escape([document.company.name, document.company.email].filter { !$0.isEmpty }.joined(separator: "  ·  "))
        let note = theme.footerNote.isEmpty ? "" : "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:rPr><w:sz w:val=\"13\"/><w:color w:val=\"\(mutedHex)\"/></w:rPr><w:t xml:space=\"preserve\">\(Self.escape(theme.footerNote))</w:t></w:r></w:p>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:p><w:pPr><w:tabs><w:tab w:val="right" w:pos="\(contentWidth)"/></w:tabs></w:pPr>\
        <w:r><w:rPr><w:sz w:val="14"/><w:color w:val="\(mutedHex)"/></w:rPr><w:t xml:space="preserve">\(company)</w:t></w:r>\
        <w:r><w:rPr><w:sz w:val="14"/><w:color w:val="\(mutedHex)"/></w:rPr><w:tab/><w:t xml:space="preserve">\(Self.escape(document.number))  ·  Page </w:t></w:r>\
        <w:fldSimple w:instr="PAGE"><w:r><w:rPr><w:sz w:val="14"/><w:color w:val="\(mutedHex)"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>\
        <w:r><w:rPr><w:sz w:val="14"/><w:color w:val="\(mutedHex)"/></w:rPr><w:t xml:space="preserve"> of </w:t></w:r>\
        <w:fldSimple w:instr="NUMPAGES"><w:r><w:rPr><w:sz w:val="14"/><w:color w:val="\(mutedHex)"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple></w:p>\(note)\
        </w:ftr>
        """
    }
}

extension WorkspaceStore {
    /// Writes a Word copy next to the PDF in the document's folder and returns its URL.
    @discardableResult
    public func exportDOCX(_ document: DocumentRecord, to destination: URL? = nil) throws -> URL {
        let folder = try workspace.resolve(folderPath(for: document))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = destination ?? folder.appendingPathComponent((pdfFileName(for: document) as NSString).deletingPathExtension + ".docx")
        try DocxExporter.export(document, theme: theme(for: document), logo: image(at: document.company.logoPath), to: url)
        return url
    }
}
