import AppKit

// MARK: - Storage

extension RichTextBody {
    public init(attributed: NSAttributedString) {
        let range = NSRange(location: 0, length: attributed.length)
        let data = attributed.length == 0 ? Data() : (attributed.rtfd(from: range, documentAttributes: [:]) ?? Data())
        self.init(rtfd: data, plainText: attributed.string.replacingOccurrences(of: "\u{FFFC}", with: ""))
    }

    public func attributedString() -> NSAttributedString {
        if !rtfd.isEmpty, let value = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
            return RichTextTransform.restoringListMarkers(value)
        }
        return NSAttributedString(string: plainText)
    }
}

// MARK: - Styles

/// Paragraph and character styles derived from a template, shared by starters, clauses and the editor.
public struct RichTextStyle {
    public let theme: TemplateTheme
    public var bodySize: CGFloat = 10.5

    public init(theme: TemplateTheme) {
        self.theme = theme
    }

    func font(_ name: String, _ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    public var bodyFont: NSFont { font(theme.bodyFont, bodySize) }
    public var boldFont: NSFont { font(theme.bodyBoldFont, bodySize, weight: .semibold) }

    public func paragraph(spacingAfter: CGFloat = 7, spacingBefore: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    public var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph()]
    }

    public func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        switch level {
        case 1:
            [.font: font(theme.headingFont, 17, weight: .bold), .foregroundColor: theme.ink.nsColor, .paragraphStyle: paragraph(spacingAfter: 8, spacingBefore: 6)]
        default:
            [.font: font(theme.bodyBoldFont, 12, weight: .semibold), .foregroundColor: theme.accent.nsColor, .paragraphStyle: paragraph(spacingAfter: 5, spacingBefore: 8)]
        }
    }

    public static let orderedMarker = NSTextList.MarkerFormat("{decimal}.")

    public func listParagraph(ordered: Bool, list: NSTextList? = nil) -> NSMutableParagraphStyle {
        let style = paragraph(spacingAfter: 4)
        style.textLists = [list ?? NSTextList(markerFormat: ordered ? Self.orderedMarker : .disc, options: 0)]
        style.tabStops = [NSTextTab(textAlignment: .left, location: 8), NSTextTab(textAlignment: .left, location: 24)]
        style.headIndent = 24
        style.firstLineHeadIndent = 0
        return style
    }

    /// A paragraph with inline `**bold**` support.
    public func inline(_ text: String, attributes: [NSAttributedString.Key: Any]? = nil) -> NSMutableAttributedString {
        let base = attributes ?? bodyAttributes
        let result = NSMutableAttributedString()
        let parts = text.components(separatedBy: "**")
        for (index, part) in parts.enumerated() where !part.isEmpty {
            var attrs = base
            if index % 2 == 1 { attrs[.font] = boldFont }
            result.append(NSAttributedString(string: part, attributes: attrs))
        }
        return result
    }

    public func table(rows: [[String]]) -> NSAttributedString {
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return NSAttributedString() }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.setContentWidth(100, type: .percentageValueType)
        let result = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(NSColor(white: 0.75, alpha: 1))
                block.setWidth(5, type: .absoluteValueType, for: .padding)
                block.setContentWidth(CGFloat(100) / CGFloat(columns), type: .percentageValueType)
                if rowIndex == 0 { block.backgroundColor = theme.tint.nsColor }
                let style = paragraph(spacingAfter: 0)
                style.textBlocks = [block]
                var attributes = bodyAttributes
                attributes[.paragraphStyle] = style
                if rowIndex == 0 { attributes[.font] = boldFont }
                let text = column < row.count ? row[column] : ""
                result.append(inline(text + "\n", attributes: attributes))
            }
        }
        return result
    }

    /// An empty `rows × columns` table for the editor's Insert Table command.
    public func emptyTable(rows: Int, columns: Int) -> NSAttributedString {
        let header = (1...columns).map { "Column \($0)" }
        return table(rows: [header] + Array(repeating: Array(repeating: " ", count: columns), count: max(1, rows - 1)))
    }

    /// A form feed in its own paragraph. The editor shows it as a rule (via a text block border);
    /// printing removes the rule and the form feed moves the text to the next page.
    public var pageBreak: NSAttributedString {
        let block = NSTextBlock()
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setBorderColor(NSColor(white: 0.7, alpha: 1), for: .maxY)
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(10, type: .absoluteValueType, for: .margin, edge: .maxY)
        let style = paragraph(spacingAfter: 0)
        style.textBlocks = [block]
        style.alignment = .center
        var attributes = bodyAttributes
        attributes[.paragraphStyle] = style
        attributes[.font] = NSFont.systemFont(ofSize: 8, weight: .medium)
        attributes[.foregroundColor] = NSColor(white: 0.55, alpha: 1)
        // The label is only for the editor; printing strips everything after the form feed.
        return NSAttributedString(string: "\u{000C}PAGE BREAK\n", attributes: attributes)
    }
}

// MARK: - Markup

/// Builds rich text from a small line-based markup used by starters and clauses:
/// `# Heading`, `## Subheading`, `- bullet`, `1. numbered`, `| a | b |` table rows,
/// `---` page break and inline `**bold**`. Blank lines are ignored.
public enum RichTextBuilder {
    public static func build(_ markup: String, theme: TemplateTheme) -> NSAttributedString {
        let style = RichTextStyle(theme: theme)
        let result = NSMutableAttributedString()
        var tableRows: [[String]] = []
        // Consecutive numbered lines share one list so numbering continues.
        var orderedList: NSTextList?

        // Headings are already bold, so **markers** inside them are dropped.
        func heading(_ title: String, level: Int) -> NSAttributedString {
            NSAttributedString(string: title.replacingOccurrences(of: "**", with: "") + "\n", attributes: style.headingAttributes(level: level))
        }

        func flushTable() {
            guard !tableRows.isEmpty else { return }
            result.append(style.table(rows: tableRows))
            tableRows = []
        }

        for rawLine in markup.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                tableRows.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map {
                    $0.trimmingCharacters(in: .whitespaces)
                })
                continue
            }
            flushTable()
            if line.isEmpty { continue }
            if line.range(of: #"^\d+\.\s"#, options: .regularExpression) == nil { orderedList = nil }
            if line == "---" {
                result.append(style.pageBreak)
            } else if line.range(of: #"^#{3,}\s"#, options: .regularExpression) != nil {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                result.append(heading(title, level: 2))
            } else if line.hasPrefix("## ") {
                result.append(heading(String(line.dropFirst(3)), level: 2))
            } else if line.hasPrefix("# ") {
                result.append(heading(String(line.dropFirst(2)), level: 1))
            } else if line.hasPrefix("- ") {
                var attributes = style.bodyAttributes
                attributes[.paragraphStyle] = style.listParagraph(ordered: false)
                result.append(style.inline("\t•\t" + line.dropFirst(2) + "\n", attributes: attributes))
            } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let list = orderedList ?? NSTextList(markerFormat: RichTextStyle.orderedMarker, options: 0)
                orderedList = list
                var attributes = style.bodyAttributes
                attributes[.paragraphStyle] = style.listParagraph(ordered: true, list: list)
                let number = line[match].trimmingCharacters(in: .whitespaces)
                result.append(style.inline("\t\(number)\t" + line[match.upperBound...] + "\n", attributes: attributes))
            } else {
                result.append(style.inline(line + "\n"))
            }
        }
        flushTable()
        return result
    }
}

// MARK: - Merge fields

/// `{{client.name}}`-style placeholders filled in when a document is rendered or exported, so
/// starter text stays correct when the client or date changes later.
public enum MergeFields {
    public struct Field: Identifiable, Hashable, Sendable {
        public let token: String
        public let label: String
        public var id: String { token }
    }

    public static let all: [Field] = [
        Field(token: "client.name", label: "Client name"),
        Field(token: "client.contact", label: "Client contact person"),
        Field(token: "client.address", label: "Client address"),
        Field(token: "client.email", label: "Client email"),
        Field(token: "client.tax_id", label: "Client tax ID"),
        Field(token: "company.name", label: "Your company name"),
        Field(token: "company.address", label: "Your company address"),
        Field(token: "company.signatory", label: "Authorised signatory"),
        Field(token: "company.email", label: "Your company email"),
        Field(token: "company.phone", label: "Your company phone"),
        Field(token: "company.tax_id", label: "Your tax ID"),
        Field(token: "document.number", label: "Document number"),
        Field(token: "document.date", label: "Document date"),
        Field(token: "document.valid_until", label: "Valid until / due date"),
        Field(token: "document.title", label: "Document title"),
        Field(token: "document.total", label: "Document total"),
    ]

    public static func values(for document: DocumentRecord) -> [String: String] {
        let company = document.company
        let client = document.customer
        let blank = "________"
        func or(_ value: String) -> String { value.trimmingCharacters(in: .whitespaces).isEmpty ? blank : value }
        return [
            "client.name": or(client.name),
            "client.contact": or(client.contactPerson.isEmpty ? client.name : client.contactPerson),
            "client.address": or(client.billingAddress.lines.joined(separator: ", ")),
            "client.email": or(client.email),
            "client.tax_id": or(client.taxID),
            "company.name": or(company.displayLegalName),
            "company.address": or(company.address.lines.joined(separator: ", ")),
            "company.signatory": or(company.signatoryName),
            "company.email": or(company.email),
            "company.phone": or(company.phone),
            "company.tax_id": or(company.taxID),
            "document.number": document.number,
            "document.date": document.issueDate.display,
            "document.valid_until": document.dueDate?.display ?? blank,
            "document.title": or(document.displayTitle),
            "document.total": MoneyFormatter.format(document.totals.grandTotal, currency: document.currency),
        ].merging(customFieldValues(for: document)) { current, _ in current }
    }

    /// `{{field.<key>}}` values from custom document types and bulk generation.
    static func customFieldValues(for document: DocumentRecord) -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in document.customFields {
            let field = document.customType?.fields.first { $0.id == key }
            values["field.\(key)"] = field?.display(value) ?? value
        }
        return values
    }

    public static func apply(to text: NSAttributedString, document: DocumentRecord) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        guard let expression = try? NSRegularExpression(pattern: #"\{\{\s*([a-z_.]+)\s*\}\}"#) else { return result }
        let values = values(for: document)
        let matches = expression.matches(in: result.string, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            let key = (result.string as NSString).substring(with: match.range(at: 1))
            if let value = values[key] {
                result.replaceCharacters(in: match.range, with: value)
            }
        }
        return result
    }

    public static func apply(to text: String, document: DocumentRecord) -> String {
        apply(to: NSAttributedString(string: text), document: document).string
    }
}

// MARK: - Restyling and normalising

public enum RichTextTransform {
    /// Removes the on-screen page-break rule before printing; the form feed itself stays.
    public static func preparedForPrint(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        var location = 0
        while location < result.length {
            let string = result.string as NSString
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let paragraph = string.substring(with: range)
            if paragraph.hasPrefix("\u{000C}") {
                if let style = result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                   !style.textBlocks.isEmpty, !(style.textBlocks.first is NSTextTableBlock) {
                    let plain = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    plain.textBlocks = []
                    result.addAttribute(.paragraphStyle, value: plain, range: range)
                }
                // Drop the editor-only label that follows the form feed.
                let labelLength = range.length - 1 - (paragraph.hasSuffix("\n") ? 1 : 0)
                if labelLength > 0 {
                    result.deleteCharacters(in: NSRange(location: range.location + 1, length: labelLength))
                }
                location = range.location + range.length - max(labelLength, 0)
                continue
            }
            location = NSMaxRange(range)
        }
        return result
    }

    /// RTF stores list markers separately (`\listtext`) and the reader drops them, so put the
    /// visible `\t•\t` / `\t1.\t` markers back for paragraphs that belong to a list.
    public static func restoringListMarkers(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        var insertions: [(Int, String, [NSAttributedString.Key: Any])] = []
        let string = result.string as NSString
        var location = 0
        var previousList: NSTextList?
        var itemNumber = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            if let list = style?.textLists.last {
                itemNumber = list === previousList ? itemNumber + 1 : list.startingItemNumber
                previousList = list
                if range.length == 0 || string.character(at: range.location) != 0x09 {
                    var attributes = result.attributes(at: range.location, effectiveRange: nil)
                    attributes.removeValue(forKey: .attachment)
                    insertions.append((range.location, "\t\(list.marker(forItemNumber: itemNumber))\t", attributes))
                }
            } else {
                previousList = nil
            }
            location = NSMaxRange(range)
        }
        for (index, marker, attributes) in insertions.reversed() {
            result.insert(NSAttributedString(string: marker, attributes: attributes), at: index)
        }
        return result
    }

    /// Moves text set in the old template's fonts onto the new template's fonts, keeping sizes.
    /// Fonts the user picked themselves are left alone.
    public static func restyle(_ text: NSAttributedString, from old: TemplateTheme, to new: TemplateTheme) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        // Some styles share one font for headings and bold text, so later pairs win on duplicates.
        let map = Dictionary([(old.headingFont, new.headingFont), (old.bodyBoldFont, new.bodyBoldFont), (old.bodyFont, new.bodyFont)],
                             uniquingKeysWith: { _, last in last })
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let font = value as? NSFont, let target = map[font.fontName],
                  let replacement = NSFont(name: target, size: font.pointSize) else { return }
            result.addAttribute(.font, value: replacement, range: range)
        }
        result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            if abs(color.redComponent - old.accent.red) < 0.01, abs(color.greenComponent - old.accent.green) < 0.01,
               abs(color.blueComponent - old.accent.blue) < 0.01 {
                result.addAttribute(.foregroundColor, value: new.accent.nsColor, range: range)
            }
        }
        return result
    }

    /// Shrinks images that are wider or taller than the printable area.
    public static func fitAttachments(_ text: NSAttributedString, maxSize: CGSize) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let image = image(of: attachment) else { return }
            let size = image.size
            guard size.width > 0, size.height > 0, size.width > maxSize.width || size.height > maxSize.height else { return }
            let ratio = min(maxSize.width / size.width, maxSize.height / size.height)
            let replacement = NSTextAttachment()
            replacement.attachmentCell = NSTextAttachmentCell(imageCell: resized(image, to: CGSize(width: size.width * ratio, height: size.height * ratio)))
            result.addAttribute(.attachment, value: replacement, range: range)
        }
        return result
    }

    public static func image(of attachment: NSTextAttachment) -> NSImage? {
        if let image = (attachment.attachmentCell as? NSTextAttachmentCell)?.image { return image }
        if let image = attachment.image { return image }
        if let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents { return NSImage(data: data) }
        return nil
    }

    public static func resized(_ image: NSImage, to size: CGSize) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        return output
    }

    /// An attachment that survives RTFD round trips (stored as PNG data).
    public static func imageAttachment(_ image: NSImage, maxWidth: CGFloat) -> NSAttributedString {
        var picture = image
        if image.size.width > maxWidth {
            let ratio = maxWidth / image.size.width
            picture = resized(image, to: CGSize(width: image.size.width * ratio, height: image.size.height * ratio))
        }
        guard let tiff = picture.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return NSAttributedString() }
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "image.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: picture)
        return NSAttributedString(attachment: attachment)
    }
}
