import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a `DocumentRecord` to PDF with Core Graphics.
///
/// Layout runs first and produces a list of drawing operations per page; drawing happens in a
/// second pass, so footers can show "Page X of Y" and tests can inspect pagination.
public enum DocumentRenderer {
    public struct Output {
        public let data: Data
        public let pageCount: Int
        public let usedFallbackTemplate: Bool

        public init(data: Data, pageCount: Int, usedFallbackTemplate: Bool) {
            self.data = data
            self.pageCount = pageCount
            self.usedFallbackTemplate = usedFallbackTemplate
        }
    }

    /// `theme` comes from `WorkspaceStore.theme(for:)` for custom templates. Without it, an issued
    /// document uses its saved snapshot and anything else falls back to the built-in library.
    public static func render(_ document: DocumentRecord, logo: NSImage? = nil, theme: TemplateTheme? = nil) -> Output {
        var fallback = false
        let resolvedTheme: TemplateTheme
        if let theme {
            resolvedTheme = theme
        } else if document.status.isContentLocked, let snapshot = document.templateSnapshot {
            resolvedTheme = snapshot
        } else {
            let resolved = TemplateLibrary.resolve(id: document.templateID, kind: document.kind)
            resolvedTheme = resolved.template.theme
            fallback = resolved.isFallback
        }
        let totals = DocumentCalculator.totals(for: document)
        var size = document.pageSize.points
        if document.orientation == .landscape { size = CGSize(width: size.height, height: size.width) }

        let builder = LayoutBuilder(document: document, totals: totals, theme: resolvedTheme, logo: logo, pageSize: size)
        let pages = builder.build()
        let data = draw(pages: pages, builder: builder, document: document, size: size)
        return Output(data: data, pageCount: pages.count, usedFallbackTemplate: fallback)
    }

    public static func pdfData(for document: DocumentRecord, logo: NSImage? = nil, theme: TemplateTheme? = nil) -> Data {
        render(document, logo: logo, theme: theme).data
    }

    private static func draw(pages: [[DrawOp]], builder: LayoutBuilder, document: DocumentRecord, size: CGSize) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: size)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: document.usesBody && !document.title.isEmpty ? "\(document.title) \(document.number)" : "\(document.typeName) \(document.number)",
            kCGPDFContextAuthor: document.company.name,
            kCGPDFContextSubject: document.customer.name,
            kCGPDFContextCreator: "DocuDesk for Mac",
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return Data() }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        for (index, operations) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let footer = builder.footer(page: index + 1, of: pages.count)
            for operation in operations + footer {
                operation.perform(in: context)
            }
            if document.status == .cancelled {
                drawWatermark("CANCELLED", in: context, size: size)
            } else if !builder.theme.watermark.trimmingCharacters(in: .whitespaces).isEmpty {
                drawWatermark(builder.theme.watermark.uppercased(), in: context, size: size, color: builder.accent.withAlphaComponent(0.07))
            }
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func drawWatermark(_ text: String, in context: CGContext, size: CGSize, color: NSColor = NSColor.systemRed.withAlphaComponent(0.12)) {
        let fontSize: CGFloat = text.count > 10 ? 48 : 72
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: -.pi / 6)
        string.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
        context.restoreGState()
    }
}

// MARK: - Drawing operations

enum DrawOp {
    case text(NSAttributedString, CGRect)
    case fill(CGRect, NSColor)
    case line(CGPoint, CGPoint, NSColor, CGFloat)
    case stroke(CGRect, NSColor, CGFloat)
    case image(NSImage, CGRect)
    /// Glyphs laid out by TextKit, drawn at `origin` (the text container's top-left). The op holds
    /// the text storage because a layout manager doesn't retain its storage.
    case textFlow(NSTextStorage, NSRange, CGPoint)

    func perform(in context: CGContext) {
        switch self {
        case let .text(string, rect):
            string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        case let .fill(rect, color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case let .line(from, to, color, width):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        case let .stroke(rect, color, width):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.stroke(rect)
        case let .textFlow(storage, range, origin):
            guard let layoutManager = storage.layoutManagers.first else { return }
            layoutManager.drawBackground(forGlyphRange: range, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: range, at: origin)
        case let .image(image, rect):
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
    }
}

// MARK: - Layout

final class LayoutBuilder {
    let document: DocumentRecord
    let totals: DocumentTotals
    let theme: TemplateTheme
    let logo: NSImage?
    let pageSize: CGSize

    let margin: CGFloat
    let footerHeight: CGFloat = 26
    private(set) var pages: [[DrawOp]] = [[]]
    private(set) var y: CGFloat

    let accent: NSColor
    let ink: NSColor
    let muted: NSColor
    let tint: NSColor
    let rule = NSColor(white: 0.82, alpha: 1)

    init(document: DocumentRecord, totals: DocumentTotals, theme: TemplateTheme, logo: NSImage?, pageSize: CGSize) {
        self.document = document
        self.totals = totals
        self.theme = theme
        self.logo = logo
        self.pageSize = pageSize
        let baseMargin: CGFloat
        switch theme.density {
        case .compact: baseMargin = 30
        case .normal: baseMargin = 40
        case .spacious: baseMargin = 54
        }
        margin = pageSize.width < 500 ? baseMargin * 0.7 : baseMargin
        y = margin
        accent = theme.accent.nsColor
        ink = theme.ink.nsColor
        muted = theme.muted.nsColor
        tint = theme.tint.nsColor
    }

    var left: CGFloat { margin }
    var right: CGFloat { pageSize.width - margin }
    var width: CGFloat { right - left }
    var bottomLimit: CGFloat { pageSize.height - margin - footerHeight }
    var remaining: CGFloat { bottomLimit - y }
    /// Scales type down slightly on A5.
    var scale: CGFloat { pageSize.width < 500 ? 0.86 : 1 }
    var currency: String { document.currency }

    func add(_ operation: DrawOp) {
        pages[pages.count - 1].append(operation)
    }

    func newPage() {
        pages.append([])
        y = margin
    }

    /// Starts a new page if `height` does not fit. Returns true when a break happened.
    @discardableResult
    func ensureSpace(_ height: CGFloat) -> Bool {
        guard height > remaining, y > margin else { return false }
        newPage()
        return true
    }

    // MARK: Fonts and text

    func font(_ name: String, _ size: CGFloat, fallback weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: name, size: size * scale) ?? NSFont.systemFont(ofSize: size * scale, weight: weight)
    }

    func body(_ size: CGFloat = 9) -> NSFont { font(theme.bodyFont, size) }
    func bold(_ size: CGFloat = 9) -> NSFont { font(theme.bodyBoldFont, size, fallback: .semibold) }
    func heading(_ size: CGFloat) -> NSFont { font(theme.headingFont, size, fallback: .bold) }

    func text(_ string: String, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left, lineSpacing: CGFloat = 1.5, kern: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        if kern != 0 { attributes[.kern] = kern }
        return NSAttributedString(string: string, attributes: attributes)
    }

    func label(_ string: String, align: NSTextAlignment = .left, color: NSColor? = nil) -> NSAttributedString {
        text(string.uppercased(), bold(7), color ?? muted, align: align, kern: 0.6)
    }

    func height(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
        guard string.length > 0 else { return 0 }
        let rect = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height)
    }

    /// Adds text at (x, top) and returns its height.
    @discardableResult
    func place(_ string: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let h = height(string, width: width)
        if h > 0 { add(.text(string, CGRect(x: x, y: top, width: width, height: h + 2))) }
        return h
    }

    func money(_ value: Decimal) -> String { MoneyFormatter.number(value, currency: currency) }
    func moneyWithSymbol(_ value: Decimal) -> String { MoneyFormatter.format(value, currency: currency) }

    // MARK: Build

    func build() -> [[DrawOp]] {
        drawHeader()
        drawParties()
        drawCustomDetails()
        if document.kind == .receipt {
            drawReceiptBody()
        } else {
            if document.usesBody { drawBody() }
            // Proposals show their pricing table only when it has items; the body supplies its heading.
            if document.usesLineItems, !(document.usesBody && document.items.isEmpty) {
                drawItemsTable()
                if showPricing { drawTotals() }
            }
        }
        drawNotes()
        if !theme.hideSignature { drawSignature() }
        return pages
    }

    var documentTitle: String {
        var title = document.printedTitle
        if document.kind == .invoice, [.cgstSgst, .igst].contains(document.taxSplit) { title = "Tax Invoice" }
        // Text documents carry their own heading in the body, so the letterhead shows no title.
        if document.usesBody { title = "" }
        return theme.uppercaseTitle ? title.uppercased() : title
    }

    /// Custom fields placed in the "Details" section, two per row.
    private func drawCustomDetails() {
        let rows = document.customFieldRows(.details)
        guard !rows.isEmpty else { return }
        ensureSpace(40)
        y += place(label("Details", color: accent), x: left, top: y, width: width) + 6
        let columnWidth = (width - 20) / 2
        for pair in stride(from: 0, to: rows.count, by: 2) {
            var rowHeight: CGFloat = 0
            for (offset, entry) in rows[pair..<min(pair + 2, rows.count)].enumerated() {
                let block = NSMutableAttributedString(attributedString: text(entry.0, body(8), muted))
                block.append(text("\n" + entry.1, bold(9), ink, lineSpacing: 1.2))
                let x = left + CGFloat(offset) * (columnWidth + 20)
                rowHeight = max(rowHeight, height(block, width: columnWidth))
                if offset == 0 { ensureSpace(rowHeight + 8) }
                place(block, x: x, top: y, width: columnWidth)
            }
            y += rowHeight + 8
        }
        add(.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), rule, 0.5))
        y += 14
    }

    // MARK: Rich-text body

    /// Flows the body across as many pages as needed with TextKit. TextKit doesn't break pages at
    /// form feeds by itself, so the body is split at each form feed and every part starts a new page.
    private func drawBody() {
        let merged = RichTextTransform.preparedForPrint(MergeFields.apply(to: document.body.attributedString(), document: document))
        guard merged.length > 0, !merged.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fullPage = CGSize(width: width, height: bottomLimit - margin)
        let fitted = RichTextTransform.fitAttachments(merged, maxSize: CGSize(width: width, height: fullPage.height * 0.9))

        for (index, segment) in Self.splitAtPageBreaks(fitted).enumerated() {
            if index > 0 { newPage() }
            flow(segment)
        }
    }

    static func splitAtPageBreaks(_ text: NSAttributedString) -> [NSAttributedString] {
        let string = text.string as NSString
        var segments: [NSAttributedString] = []
        var start = 0
        var search = NSRange(location: 0, length: string.length)
        while true {
            let found = string.range(of: "\u{000C}", range: search)
            guard found.location != NSNotFound else { break }
            segments.append(text.attributedSubstring(from: NSRange(location: start, length: found.location - start)))
            start = NSMaxRange(found)
            // Skip the paragraph break that ends the page-break paragraph.
            if start < string.length, string.character(at: start) == 0x0A { start += 1 }
            search = NSRange(location: start, length: string.length - start)
        }
        segments.append(text.attributedSubstring(from: NSRange(location: start, length: string.length - start)))
        return segments.filter { !$0.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.containsAttachments }
    }

    private func flow(_ text: NSAttributedString) {
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)

        if remaining < 60 { newPage() }
        var pagesUsed = 0
        while pagesUsed < 1000 {
            let container = NSTextContainer(size: CGSize(width: width, height: remaining))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let range = layoutManager.glyphRange(for: container)
            let used = layoutManager.usedRect(for: container)
            if range.length > 0 {
                add(.textFlow(storage, range, CGPoint(x: left, y: y)))
            }
            if NSMaxRange(range) >= layoutManager.numberOfGlyphs {
                y += ceil(used.maxY) + 16
                return
            }
            if range.length == 0, y <= margin {
                // Nothing fits even on an empty page; stop rather than loop forever.
                return
            }
            newPage()
            pagesUsed += 1
        }
    }

    var companyDetailLines: [String] {
        let company = document.company
        var lines = company.address.lines
        if !company.taxID.isEmpty { lines.append("\(company.taxIDLabel): \(company.taxID)") }
        let contact = [company.phone, company.email].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !contact.isEmpty { lines.append(contact) }
        if !company.website.isEmpty { lines.append(company.website) }
        return lines
    }

    func logoSize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize? {
        guard let logo, logo.size.width > 0, logo.size.height > 0 else { return nil }
        let factor = theme.logoSize.factor
        let ratio = min(maxWidth * factor / logo.size.width, maxHeight * factor / logo.size.height)
        return CGSize(width: logo.size.width * ratio, height: logo.size.height * ratio)
    }

    // MARK: Header

    private func drawHeader() {
        switch theme.header {
        case .band: drawBandHeader()
        case .left: drawLeftHeader()
        case .split: drawSplitHeader()
        case .centered: drawCenteredHeader()
        }
    }

    private func companyBlock(color: NSColor, detailColor: NSColor, align: NSTextAlignment = .left, nameSize: CGFloat = 13) -> NSAttributedString {
        let block = NSMutableAttributedString(attributedString: text(document.company.displayLegalName, heading(nameSize), color, align: align))
        let details = companyDetailLines.joined(separator: "\n")
        if !details.isEmpty {
            block.append(text("\n", body(4), color, align: align))
            block.append(text(details, body(8), detailColor, align: align, lineSpacing: 1.2))
        }
        return block
    }

    private func drawBandHeader() {
        let pad: CGFloat = 20
        let titleWidth = width * 0.4
        let title = text(documentTitle, heading(20), .white, align: .right, kern: 1.2)
        let number = text(document.number, body(9), NSColor.white.withAlphaComponent(0.85), align: .right)
        var companyX = left
        var logoHeight: CGFloat = 0
        let logoSize = logoSize(maxWidth: 110, maxHeight: 46)
        if let logoSize {
            companyX += logoSize.width + 12
            logoHeight = logoSize.height
        }
        let companyWidth = width - titleWidth - (companyX - left) - 10
        let block = companyBlock(color: .white, detailColor: NSColor.white.withAlphaComponent(0.8))
        let blockHeight = height(block, width: companyWidth)
        let titleHeight = height(title, width: titleWidth) + 4 + height(number, width: titleWidth)
        let bandHeight = max(blockHeight, titleHeight, logoHeight) + pad * 2

        add(.fill(CGRect(x: 0, y: 0, width: pageSize.width, height: bandHeight), accent))
        if let logo, let logoSize {
            add(.image(logo, CGRect(x: left, y: pad, width: logoSize.width, height: logoSize.height)))
        }
        place(block, x: companyX, top: pad, width: companyWidth)
        let titleH = place(title, x: right - titleWidth, top: pad, width: titleWidth)
        place(number, x: right - titleWidth, top: pad + titleH + 4, width: titleWidth)
        y = bandHeight + 20
    }

    private func drawLeftHeader() {
        var leftBottom = y
        if let logo, let size = logoSize(maxWidth: 140, maxHeight: 50) {
            add(.image(logo, CGRect(x: left, y: y, width: size.width, height: size.height)))
            leftBottom += size.height + 10
        }
        let blockWidth = width * 0.55
        leftBottom += place(companyBlock(color: ink, detailColor: muted), x: left, top: leftBottom, width: blockWidth)

        let titleWidth = width * 0.42
        let title = text(documentTitle, heading(theme.uppercaseTitle ? 22 : 26), accent, align: .right, kern: theme.uppercaseTitle ? 2 : 0)
        let titleHeight = place(title, x: right - titleWidth, top: y - 4, width: titleWidth)
        let number = text(document.number, bold(10), ink, align: .right)
        let rightBottom = y + titleHeight + place(number, x: right - titleWidth, top: y + titleHeight, width: titleWidth)

        y = max(leftBottom, rightBottom) + 14
        add(.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), ink, 0.75))
        y += 16
    }

    private func drawSplitHeader() {
        let blockWidth = width * 0.55
        var leftTop = y
        if let logo, let size = logoSize(maxWidth: 130, maxHeight: 44) {
            add(.image(logo, CGRect(x: left, y: y, width: size.width, height: size.height)))
            leftTop += size.height + 8
        }
        let leftBottom = leftTop + place(companyBlock(color: ink, detailColor: muted, nameSize: 16), x: left, top: leftTop, width: blockWidth)

        let titleWidth = width * 0.42
        let titleHeight = place(text(documentTitle, heading(28), accent, align: .right), x: right - titleWidth, top: y - 6, width: titleWidth)
        let numberHeight = place(text("No. \(document.number)", body(9.5), muted, align: .right), x: right - titleWidth, top: y - 6 + titleHeight + 2, width: titleWidth)
        let rightBottom = y - 6 + titleHeight + 2 + numberHeight

        y = max(leftBottom, rightBottom) + 12
        add(.fill(CGRect(x: left, y: y, width: width, height: 1.5), accent))
        y += 18
    }

    private func drawCenteredHeader() {
        if let logo, let size = logoSize(maxWidth: 120, maxHeight: 48) {
            add(.image(logo, CGRect(x: left + (width - size.width) / 2, y: y, width: size.width, height: size.height)))
            y += size.height + 8
        }
        y += place(text(document.company.displayLegalName, heading(18), ink, align: .center), x: left, top: y, width: width) + 3
        let details = companyDetailLines.joined(separator: "   |   ")
        y += place(text(details, body(8), muted, align: .center, lineSpacing: 1.2), x: left, top: y, width: width) + 10
        add(.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), accent, 1.2))
        add(.line(CGPoint(x: left, y: y + 2.5), CGPoint(x: right, y: y + 2.5), accent, 0.4))
        y += 10
        guard !documentTitle.isEmpty else {
            y += 8
            return
        }
        y += place(text(documentTitle, heading(15), accent, align: .center, kern: 2.5), x: left, top: y, width: width) + 6
        add(.line(CGPoint(x: left + width * 0.38, y: y), CGPoint(x: right - width * 0.38, y: y), accent, 0.6))
        y += 16
    }

    // MARK: Parties and meta

    private var metaRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append((document.numberLabel, document.number))
        rows.append(("Date", document.issueDate.display))
        if let dueDate = document.dueDate, let dueLabel = document.dueDateLabel {
            rows.append((dueLabel, dueDate.display))
        }
        if !document.reference.isEmpty { rows.append(("Reference", document.reference)) }
        if !document.placeOfSupply.isEmpty { rows.append(("Place of Supply", document.placeOfSupply)) }
        if document.revision > 1 { rows.append(("Revision", "R\(document.revision)")) }
        rows += document.customFieldRows(.meta)
        return rows
    }

    private func partyBlock(_ heading: String, name: String, lines: [String]) -> NSAttributedString {
        let block = NSMutableAttributedString(attributedString: label(heading, color: accent))
        block.append(text("\n", body(5), ink))
        block.append(text(name.isEmpty ? "—" : name, bold(10.5), ink))
        if !lines.isEmpty {
            block.append(text("\n" + lines.joined(separator: "\n"), body(8.5), muted, lineSpacing: 1.2))
        }
        return block
    }

    private func drawParties() {
        let customer = document.customer
        var billLines = customer.billingAddress.lines
        if !customer.contactPerson.isEmpty { billLines.insert("Attn: \(customer.contactPerson)", at: 0) }
        if !customer.taxID.isEmpty { billLines.append("\(document.company.taxIDLabel): \(customer.taxID)") }
        let contact = [customer.phone, customer.email].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        if !contact.isEmpty { billLines.append(contact) }

        let receivedFrom = document.kind == .receipt
        let billTo = partyBlock(document.partyLabel, name: customer.name, lines: billLines)
        let hasShipping = !customer.shippingAddress.isEmpty && !receivedFrom
        let metaWidth = width * 0.34
        let gap: CGFloat = 16
        let partyWidth = hasShipping ? (width - metaWidth - gap * 2) / 2 : width - metaWidth - gap

        let billHeight = place(billTo, x: left, top: y, width: partyWidth)
        var shipHeight: CGFloat = 0
        if hasShipping {
            let ship = partyBlock("Ship To", name: customer.name, lines: customer.shippingAddress.lines)
            shipHeight = place(ship, x: left + partyWidth + gap, top: y, width: partyWidth)
        }

        let metaX = right - metaWidth
        var metaY = y
        let labelWidth = metaWidth * 0.48
        for (title, value) in metaRows {
            let valueString = text(value, bold(9), ink, align: .right)
            let rowHeight = max(height(valueString, width: metaWidth - labelWidth), 12)
            place(text(title, body(8.5), muted), x: metaX, top: metaY, width: labelWidth)
            place(valueString, x: metaX + labelWidth, top: metaY, width: metaWidth - labelWidth)
            metaY += rowHeight + 4
        }
        if theme.table == .boxed {
            add(.stroke(CGRect(x: metaX - 6, y: y - 5, width: metaWidth + 6, height: metaY - y + 4), rule, 0.5))
        }
        y = max(y + billHeight, y + shipHeight, metaY) + 18
    }

    // MARK: Items table

    private struct Column {
        let title: String
        let width: CGFloat
        let align: NSTextAlignment
    }

    private lazy var showPricing = document.showsPricing
    private lazy var showHSN = !theme.hideHSN && document.items.contains { !$0.hsnSac.isEmpty }
    private lazy var showDiscount = totals.lines.contains { $0.lineDiscount > 0 }
    private lazy var showTax = !theme.hideTaxColumn && document.taxSplit != .none && totals.lines.contains { $0.taxRate > 0 }

    private lazy var columns: [Column] = {
        var fixed: [Column] = theme.hideItemNumbers ? [] : [Column(title: "#", width: 22, align: .left)]
        var trailing: [Column] = []
        if showHSN { trailing.append(Column(title: "HSN/SAC", width: 54, align: .left)) }
        trailing.append(Column(title: "Qty", width: 52, align: .right))
        if showPricing {
            trailing.append(Column(title: "Rate", width: 70, align: .right))
            if showDiscount { trailing.append(Column(title: "Disc.", width: 54, align: .right)) }
            if showTax { trailing.append(Column(title: "Tax", width: 40, align: .right)) }
            trailing.append(Column(title: "Amount", width: 80, align: .right))
        }
        let used = (fixed + trailing).reduce(0) { $0 + $1.width * scale }
        let itemTitle = theme.itemColumnTitle.trimmingCharacters(in: .whitespaces)
        fixed.append(Column(title: itemTitle.isEmpty ? "Item & Description" : itemTitle, width: (width - used) / scale, align: .left))
        return fixed + trailing
    }()

    private let cellPadX: CGFloat = 5
    private var cellPadY: CGFloat {
        switch theme.density {
        case .compact: 4
        case .normal: 6
        case .spacious: 8
        }
    }

    private func headerColor() -> NSColor {
        switch theme.table {
        case .striped: .white
        case .lined: accent
        case .boxed: ink
        case .minimal: muted
        }
    }

    private func drawTableHeader() {
        let rowHeight: CGFloat = 22
        switch theme.table {
        case .striped: add(.fill(CGRect(x: left, y: y, width: width, height: rowHeight), accent))
        case .boxed: add(.fill(CGRect(x: left, y: y, width: width, height: rowHeight), tint))
        case .lined, .minimal: break
        }
        var x = left
        for column in columns {
            let w = column.width * scale
            let string = label(column.title, align: column.align, color: headerColor())
            let h = height(string, width: w - cellPadX * 2)
            place(string, x: x + cellPadX, top: y + (rowHeight - h) / 2, width: w - cellPadX * 2)
            if theme.table == .boxed { add(.stroke(CGRect(x: x, y: y, width: w, height: rowHeight), rule, 0.5)) }
            x += w
        }
        switch theme.table {
        case .lined: add(.line(CGPoint(x: left, y: y + rowHeight), CGPoint(x: right, y: y + rowHeight), accent, 1))
        case .minimal: add(.line(CGPoint(x: left, y: y + rowHeight), CGPoint(x: right, y: y + rowHeight), ink, 0.75))
        default: break
        }
        y += rowHeight
    }

    private func cells(for index: Int, item: LineItem) -> [NSAttributedString] {
        let line = totals.line(for: item.id) ?? LineTotal(itemID: item.id)
        let description = NSMutableAttributedString(attributedString: text(item.name.isEmpty ? "Item" : item.name, bold(9), ink))
        if !item.details.isEmpty {
            description.append(text("\n" + item.details, body(8), muted, lineSpacing: 1.1))
        }
        var result: [NSAttributedString] = theme.hideItemNumbers ? [description] : [text("\(index + 1)", body(8.5), muted), description]
        if showHSN { result.append(text(item.hsnSac, body(8.5), ink)) }
        let quantity = MoneyFormatter.quantity(item.quantity) + (item.unit.isEmpty ? "" : " \(item.unit)")
        result.append(text(quantity, body(8.5), ink, align: .right))
        guard showPricing else { return result }
        result.append(text(money(item.unitPrice), body(8.5), ink, align: .right))
        if showDiscount {
            let discount = line.lineDiscount > 0
                ? (item.discountKind == .percent ? "\(MoneyFormatter.quantity(item.discountValue))%" : money(line.lineDiscount))
                : "—"
            result.append(text(discount, body(8.5), ink, align: .right))
        }
        if showTax { result.append(text("\(MoneyFormatter.quantity(line.taxRate))%", body(8.5), ink, align: .right)) }
        result.append(text(money(line.net), bold(8.5), ink, align: .right))
        return result
    }

    private func drawItemsTable() {
        ensureSpace(22 + 40)
        drawTableHeader()
        if document.items.isEmpty {
            y += place(text("No line items yet.", body(9), muted, align: .center), x: left, top: y + 12, width: width) + 24
            return
        }
        for (index, item) in document.items.enumerated() {
            let rowCells = cells(for: index, item: item)
            let rowHeight = zip(rowCells, columns).map { height($0, width: $1.width * scale - cellPadX * 2) }.max().map { $0 + cellPadY * 2 } ?? 20
            if rowHeight > remaining {
                if theme.table == .minimal { add(.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), rule, 0.5)) }
                newPage()
                place(text("\(document.typeName) \(document.number), continued", body(8), muted), x: left, top: y, width: width)
                y += 16
                drawTableHeader()
            }
            if theme.table == .striped, index % 2 == 1 {
                add(.fill(CGRect(x: left, y: y, width: width, height: rowHeight), tint))
            }
            var x = left
            for (cell, column) in zip(rowCells, columns) {
                let w = column.width * scale
                place(cell, x: x + cellPadX, top: y + cellPadY, width: w - cellPadX * 2)
                if theme.table == .boxed { add(.stroke(CGRect(x: x, y: y, width: w, height: rowHeight), rule, 0.5)) }
                x += w
            }
            y += rowHeight
            if theme.table == .lined || theme.table == .striped {
                add(.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), rule, 0.5))
            }
        }
        if theme.table == .minimal {
            add(.line(CGPoint(x: left, y: y), CGPoint(x: right, y: y), ink, 0.75))
        }
        y += 12
    }

    // MARK: Totals

    private func drawTotals() {
        var rows: [(String, String, Bool)] = []
        rows.append(("Subtotal", money(totals.subtotal), false))
        if totals.documentDiscount > 0 {
            let suffix = document.documentDiscountKind == .percent ? " (\(MoneyFormatter.quantity(document.documentDiscountValue))%)" : ""
            rows.append(("Discount\(suffix)", "−" + money(totals.documentDiscount), false))
        }
        if !totals.taxLines.isEmpty, totals.taxableAmount != totals.subtotal || document.taxMode == .inclusive {
            rows.append(("Taxable value", money(totals.taxableAmount), false))
        }
        for tax in totals.taxLines { rows.append((tax.label, money(tax.amount), false)) }
        if totals.shipping != 0 { rows.append(("Shipping", money(totals.shipping), false)) }
        if totals.adjustment != 0 { rows.append((document.adjustmentLabel.isEmpty ? "Adjustment" : document.adjustmentLabel, money(totals.adjustment), false)) }
        if totals.roundOff != 0 { rows.append(("Round off", money(totals.roundOff), false)) }

        let rowHeight: CGFloat = 16 * scale + 2
        let totalHeight: CGFloat = 26
        let settledRows = (totals.advancePaid > 0 ? 1 : 0) + (totals.amountPaid > 0 ? 1 : 0)
        let extra = settledRows > 0 ? rowHeight * CGFloat(settledRows + 1) + 6 : 0
        let blockWidth = min(250, width * 0.48)
        let blockX = right - blockWidth
        let wordsWidth = width - blockWidth - 24
        let words = NSMutableAttributedString()
        if !theme.hideAmountInWords {
            words.append(label("Amount in words"))
            words.append(text("\n" + totals.amountInWords, bold(9), ink, lineSpacing: 1.3))
        }
        if document.taxMode == .inclusive, !totals.taxLines.isEmpty {
            words.append(text("\nPrices are inclusive of tax.", body(7.5), muted))
        }
        let wordsHeight = height(words, width: wordsWidth)
        let blockHeight = CGFloat(rows.count) * rowHeight + totalHeight + extra + 8
        ensureSpace(max(blockHeight, wordsHeight))

        let top = y
        place(words, x: left, top: top + 2, width: wordsWidth)

        var rowY = top
        for (title, value, _) in rows {
            place(text(title, body(8.5), muted), x: blockX, top: rowY, width: blockWidth * 0.6)
            place(text(value, body(9), ink, align: .right), x: blockX + blockWidth * 0.4, top: rowY, width: blockWidth * 0.6)
            rowY += rowHeight
        }
        rowY += 2
        let grandText = moneyWithSymbol(totals.grandTotal)
        switch theme.table {
        case .striped, .boxed:
            add(.fill(CGRect(x: blockX - 6, y: rowY, width: blockWidth + 6, height: totalHeight), theme.table == .striped ? accent : tint))
            let color: NSColor = theme.table == .striped ? .white : ink
            place(text("Total", bold(10), color), x: blockX, top: rowY + 7, width: blockWidth * 0.5)
            place(text(grandText, bold(11), color, align: .right), x: blockX + blockWidth * 0.3, top: rowY + 6, width: blockWidth * 0.7 - 4)
        case .lined, .minimal:
            add(.line(CGPoint(x: blockX, y: rowY), CGPoint(x: right, y: rowY), theme.table == .lined ? accent : ink, 1))
            place(text("Total", bold(10), ink), x: blockX, top: rowY + 7, width: blockWidth * 0.5)
            place(text(grandText, bold(11), theme.table == .lined ? accent : ink, align: .right), x: blockX + blockWidth * 0.3, top: rowY + 6, width: blockWidth * 0.7)
        }
        rowY += totalHeight
        if settledRows > 0 {
            rowY += 6
            if totals.advancePaid > 0 {
                place(text("Advance received", body(8.5), muted), x: blockX, top: rowY, width: blockWidth * 0.6)
                place(text("−" + money(totals.advancePaid), body(9), ink, align: .right), x: blockX + blockWidth * 0.4, top: rowY, width: blockWidth * 0.6)
                rowY += rowHeight
            }
            if totals.amountPaid > 0 {
                place(text("Amount paid", body(8.5), muted), x: blockX, top: rowY, width: blockWidth * 0.6)
                place(text("−" + money(totals.amountPaid), body(9), ink, align: .right), x: blockX + blockWidth * 0.4, top: rowY, width: blockWidth * 0.6)
                rowY += rowHeight
            }
            place(text("Balance due", bold(9), ink), x: blockX, top: rowY, width: blockWidth * 0.6)
            place(text(moneyWithSymbol(totals.balanceDue), bold(9.5), accent, align: .right), x: blockX + blockWidth * 0.4, top: rowY, width: blockWidth * 0.6)
            rowY += rowHeight
        }
        y = max(rowY, top + wordsHeight) + 20
    }

    // MARK: Receipt

    private func drawReceiptBody() {
        guard let receipt = document.receipt else { return }
        let boxHeight: CGFloat = 74
        ensureSpace(boxHeight + 80)
        add(.fill(CGRect(x: left, y: y, width: width, height: boxHeight), tint))
        add(.fill(CGRect(x: left, y: y, width: 4, height: boxHeight), accent))
        place(label("Amount received"), x: left + 18, top: y + 14, width: width * 0.5)
        place(text(moneyWithSymbol(totals.grandTotal), heading(24), accent), x: left + 18, top: y + 28, width: width * 0.55)

        var details: [(String, String)] = [("Payment method", receipt.method.displayName)]
        if !receipt.transactionReference.isEmpty { details.append(("Transaction ref.", receipt.transactionReference)) }
        if !receipt.againstDocumentNumber.isEmpty { details.append(("Against invoice", receipt.againstDocumentNumber)) }
        let detailX = left + width * 0.55
        let detailWidth = width * 0.45 - 18
        var detailY = y + 14
        for (title, value) in details {
            place(text(title, body(8.5), muted), x: detailX, top: detailY, width: detailWidth * 0.5)
            place(text(value, bold(9), ink, align: .right), x: detailX + detailWidth * 0.4, top: detailY, width: detailWidth * 0.6)
            detailY += 16
        }
        y += boxHeight + 20

        let sentence = NSMutableAttributedString(attributedString: text("Received with thanks from ", body(10), ink, lineSpacing: 3))
        sentence.append(text(document.customer.name.isEmpty ? "—" : document.customer.name, bold(10), ink, lineSpacing: 3))
        sentence.append(text(" the sum of ", body(10), ink, lineSpacing: 3))
        sentence.append(text(totals.amountInWords, bold(10), ink, lineSpacing: 3))
        sentence.append(text(" by \(receipt.method.displayName.lowercased())", body(10), ink, lineSpacing: 3))
        if !receipt.againstDocumentNumber.isEmpty {
            sentence.append(text(" towards invoice \(receipt.againstDocumentNumber)", body(10), ink, lineSpacing: 3))
        }
        if !receipt.purpose.isEmpty {
            sentence.append(text(" for \(receipt.purpose)", body(10), ink, lineSpacing: 3))
        }
        sentence.append(text(".", body(10), ink, lineSpacing: 3))
        y += place(sentence, x: left, top: y, width: width) + 24
    }

    // MARK: Notes, terms, signature

    private func drawNotes() {
        drawPaymentQR()
        let sections = theme.orderedSections.map { section -> (String, String) in
            switch section {
            case .payment: ("Payment details", document.paymentDetails)
            case .notes: ("Notes", document.notes)
            case .terms: ("Terms & conditions", document.terms)
            }
        }
        .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for (title, content) in sections {
            let heading = label(title, color: accent)
            let paragraphs = content.components(separatedBy: "\n")
            let firstParagraph = text(paragraphs.first ?? "", body(8.5), ink, lineSpacing: 1.3)
            ensureSpace(height(heading, width: width) + 4 + height(firstParagraph, width: width))
            y += place(heading, x: left, top: y, width: width) + 4
            // Page breaks happen between paragraphs so long terms flow across pages.
            for paragraph in paragraphs {
                let string = text(paragraph.isEmpty ? " " : paragraph, body(8.5), ink, lineSpacing: 1.3)
                ensureSpace(height(string, width: width))
                y += place(string, x: left, top: y, width: width) + 1
            }
            y += 14
        }
    }

    /// UPI deep link for the balance due, e.g. `upi://pay?pa=shop@okhdfc&pn=Shop&am=1180.00&cu=INR&tn=INV-1`.
    var upiLink: String? {
        let upi = document.company.upiID.trimmingCharacters(in: .whitespaces)
        guard theme.showPaymentQR, !upi.isEmpty, document.kind == .invoice, document.currency == "INR", totals.balanceDue > 0,
              document.status != .paid, document.status != .cancelled else { return nil }
        var components = URLComponents()
        components.scheme = "upi"
        components.host = "pay"
        components.queryItems = [
            URLQueryItem(name: "pa", value: upi),
            URLQueryItem(name: "pn", value: document.company.displayLegalName),
            URLQueryItem(name: "am", value: totals.balanceDue.rounded(2).plainString),
            URLQueryItem(name: "cu", value: "INR"),
            URLQueryItem(name: "tn", value: document.number),
        ]
        return components.string
    }

    static func qrImage(for text: String, side: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: CGSize(width: side, height: side))
    }

    private func drawPaymentQR() {
        guard let link = upiLink, let image = Self.qrImage(for: link, side: 84) else { return }
        ensureSpace(100)
        add(.image(image, CGRect(x: left, y: y, width: 84, height: 84)))
        let caption = NSMutableAttributedString(attributedString: label("Scan to pay with UPI", color: accent))
        caption.append(text("\n\(moneyWithSymbol(totals.balanceDue)) to \(document.company.upiID)\nWorks with any UPI app. Please quote \(document.number).",
                            body(8.5), ink, lineSpacing: 1.3))
        place(caption, x: left + 96, top: y + 16, width: width - 96)
        y += 98
    }

    private func drawSignature() {
        let blockWidth: CGFloat = 200
        ensureSpace(document.kind == .agreement ? 100 : 78)
        y += 6
        let name = document.company.signatoryName.trimmingCharacters(in: .whitespaces)
        let signatory = name.isEmpty || name.caseInsensitiveCompare("Authorised Signatory") == .orderedSame ? "Authorised Signatory" : "\(name)\nAuthorised Signatory"
        let companyHeight = signatureBlock(x: right - blockWidth, width: blockWidth, heading: "For \(document.company.displayLegalName)", caption: signatory,
                                           dated: document.kind == .agreement)
        if document.kind == .agreement {
            // Both parties sign an agreement.
            let client = document.customer.name.isEmpty ? "the Client" : document.customer.name
            let contact = document.customer.contactPerson.isEmpty ? "Authorised Signatory" : "\(document.customer.contactPerson)\nAuthorised Signatory"
            _ = signatureBlock(x: left, width: blockWidth, heading: "For \(client)", caption: contact, dated: true)
        }
        y += companyHeight
    }

    /// Draws a signature block at the current `y` without advancing it; returns its height.
    private func signatureBlock(x: CGFloat, width blockWidth: CGFloat, heading: String, caption: String, dated: Bool) -> CGFloat {
        var top = y
        top += place(text(heading, bold(9), ink, align: .center), x: x, top: top, width: blockWidth)
        top += 34
        add(.line(CGPoint(x: x + 20, y: top), CGPoint(x: x + blockWidth - 20, y: top), muted, 0.5))
        top += 4
        top += place(text(caption + (dated ? "\nDate: ____________" : ""), body(8), muted, align: .center), x: x, top: top, width: blockWidth)
        return top - y
    }

    func footer(page: Int, of count: Int) -> [DrawOp] {
        let top = pageSize.height - margin - 12
        var ops: [DrawOp] = [.line(CGPoint(x: left, y: top - 6), CGPoint(x: right, y: top - 6), rule, 0.5)]
        let company = [document.company.name, document.company.email, document.company.phone].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        let leftText = text(company, body(7), muted)
        ops.append(.text(leftText, CGRect(x: left, y: top, width: width * 0.7, height: 12)))
        let pageText = text("\(document.number)  ·  Page \(page) of \(count)", body(7), muted, align: .right)
        ops.append(.text(pageText, CGRect(x: right - width * 0.4, y: top, width: width * 0.4, height: 12)))
        if !theme.footerNote.isEmpty {
            ops.append(.text(text(theme.footerNote, body(6.5), muted, align: .center), CGRect(x: left, y: top + 10, width: width, height: 10)))
        }
        return ops
    }
}

extension RGBColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}
