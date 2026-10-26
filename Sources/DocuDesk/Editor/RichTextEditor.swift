import AppKit
import DocuDeskCore
import SwiftUI
import UniformTypeIdentifiers

/// Drives the AppKit text view from SwiftUI toolbar buttons. Every edit goes through
/// `shouldChangeText` / `didChangeText` so undo, autosave and the live preview all see it.
@MainActor
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?
    var theme: TemplateTheme
    var onChange: ((NSAttributedString) -> Void)?

    init(theme: TemplateTheme) {
        self.theme = theme
    }

    private var style: RichTextStyle { RichTextStyle(theme: theme) }

    private func edit(_ range: NSRange, _ change: (NSTextStorage) -> Void) {
        guard let textView, let storage = textView.textStorage, textView.isEditable,
              textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change(storage)
        storage.endEditing()
        textView.didChangeText()
    }

    private var selectedParagraphs: NSRange {
        guard let textView else { return NSRange(location: 0, length: 0) }
        return (textView.string as NSString).paragraphRange(for: textView.selectedRange())
    }

    // MARK: Character styles

    func toggle(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else {
            var typing = textView.typingAttributes
            if let font = typing[.font] as? NSFont {
                let has = NSFontManager.shared.traits(of: font).contains(trait)
                typing[.font] = has ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
                textView.typingAttributes = typing
            }
            return
        }
        let first = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        let adding = !(first.map { NSFontManager.shared.traits(of: $0).contains(trait) } ?? false)
        edit(range) { storage in
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                guard let font = value as? NSFont else { return }
                let converted = adding ? NSFontManager.shared.convert(font, toHaveTrait: trait) : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                storage.addAttribute(.font, value: converted, range: subrange)
            }
        }
    }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        let current = textView.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        edit(range) { $0.addAttribute(.underlineStyle, value: current == 0 ? NSUnderlineStyle.single.rawValue : 0, range: range) }
    }

    // MARK: Paragraph styles

    enum Block { case heading1, heading2, body }

    func apply(_ block: Block) {
        let range = selectedParagraphs
        let attributes: [NSAttributedString.Key: Any]
        switch block {
        case .heading1: attributes = style.headingAttributes(level: 1)
        case .heading2: attributes = style.headingAttributes(level: 2)
        case .body: attributes = style.bodyAttributes
        }
        edit(range) { storage in
            storage.addAttributes(attributes, range: range)
        }
        textView?.typingAttributes = attributes
    }

    func align(_ alignment: NSTextAlignment) {
        let range = selectedParagraphs
        edit(range) { storage in
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
                let paragraph = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                paragraph.alignment = alignment
                storage.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
            }
        }
    }

    /// Turns the selected paragraphs into a list, or back into body text if they already are one.
    func toggleList(ordered: Bool) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = selectedParagraphs
        let string = storage.string as NSString
        var paragraphs: [NSRange] = []
        string.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, subrange, enclosing, _ in
            paragraphs.append(NSRange(location: subrange.location, length: enclosing.length))
        }
        if paragraphs.isEmpty { paragraphs = [range] }
        let alreadyList = (storage.attribute(.paragraphStyle, at: min(range.location, max(storage.length - 1, 0)), effectiveRange: nil) as? NSParagraphStyle)?.textLists.isEmpty == false
        let list = NSTextList(markerFormat: ordered ? RichTextStyle.orderedMarker : .disc, options: 0)
        edit(range) { storage in
            for (index, paragraph) in paragraphs.enumerated().reversed() {
                let text = storage.string as NSString
                // Strip an existing "\t<marker>\t" prefix.
                if paragraph.length > 0, text.character(at: paragraph.location) == 0x09 {
                    let rest = text.substring(with: paragraph)
                    if let second = rest.dropFirst().firstIndex(of: "\t") {
                        let length = rest.distance(from: rest.startIndex, to: second) + 1
                        storage.deleteCharacters(in: NSRange(location: paragraph.location, length: length))
                    }
                }
                let updated = (storage.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
                if alreadyList {
                    storage.addAttribute(.paragraphStyle, value: style.paragraph(), range: updated)
                } else {
                    let marker = "\t\(list.marker(forItemNumber: index + 1))\t"
                    var attributes = storage.attributes(at: min(updated.location, max(storage.length - 1, 0)), effectiveRange: nil)
                    attributes[.paragraphStyle] = style.listParagraph(ordered: ordered, list: list)
                    storage.insert(NSAttributedString(string: marker, attributes: attributes), at: updated.location)
                    let withMarker = (storage.string as NSString).paragraphRange(for: NSRange(location: updated.location, length: 0))
                    storage.addAttribute(.paragraphStyle, value: style.listParagraph(ordered: ordered, list: list), range: withMarker)
                }
            }
        }
    }

    var selectedText: String {
        guard let textView else { return "" }
        return (textView.string as NSString).substring(with: textView.selectedRange())
    }

    func replaceSelection(with text: NSAttributedString) {
        guard let textView, textView.isEditable else { return }
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: text.string) {
            textView.textStorage?.replaceCharacters(in: range, with: text)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location, length: text.length))
        }
    }

    // MARK: Inserts

    func insert(_ text: NSAttributedString, onNewParagraph: Bool = false) {
        guard let textView, textView.isEditable else { return }
        let range = textView.selectedRange()
        let content = NSMutableAttributedString()
        if onNewParagraph, range.location > 0, (textView.string as NSString).character(at: range.location - 1) != 0x0A {
            content.append(NSAttributedString(string: "\n", attributes: style.bodyAttributes))
        }
        content.append(text)
        if textView.shouldChangeText(in: range, replacementString: content.string) {
            textView.textStorage?.replaceCharacters(in: range, with: content)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + content.length, length: 0))
        }
        textView.window?.makeFirstResponder(textView)
    }

    func insertTable(rows: Int, columns: Int) {
        insert(style.emptyTable(rows: rows, columns: columns), onNewParagraph: true)
    }

    func insertPageBreak() {
        insert(style.pageBreak, onNewParagraph: true)
    }

    func insertField(_ token: String) {
        var attributes = textView?.typingAttributes ?? style.bodyAttributes
        attributes.removeValue(forKey: .attachment)
        insert(NSAttributedString(string: "{{\(token)}}", attributes: attributes))
    }

    func insertClause(_ clause: Clause) {
        insert(RichTextBuilder.build(clause.text, theme: theme), onNewParagraph: true)
    }

    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .gif]
        panel.message = "Choose an image to insert"
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        insert(RichTextTransform.imageAttachment(image, maxWidth: 480))
    }

    func insertSignatureBlock() {
        insert(RichTextBuilder.build("\n\n______________________________\nName:\nDesignation:\nDate:", theme: theme), onNewParagraph: true)
    }

    /// Lists the document's headings at the cursor. Page numbers aren't known until printing,
    /// so the contents list shows titles only.
    func insertTableOfContents() {
        guard let storage = textView?.textStorage else { return }
        let headingFont = NSFont(name: theme.headingFont, size: 17)?.fontName
        var lines = ["## Contents"]
        let string = storage.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { substring, range, _, _ in
            guard let substring, !substring.trimmingCharacters(in: .whitespaces).isEmpty, range.length > 0,
                  let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            if font.pointSize >= 15 || font.fontName == headingFont && font.pointSize >= 14 {
                lines.append("- " + substring)
            } else if font.pointSize >= 11.5, font.fontName == self.theme.bodyBoldFont,
                      let color = (storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB),
                      abs(color.redComponent - self.theme.accent.red) < 0.02 {
                lines.append("- " + substring)
            }
        }
        guard lines.count > 1 else {
            NSSound.beep()
            return
        }
        insert(RichTextBuilder.build(lines.joined(separator: "\n"), theme: theme), onNewParagraph: true)
    }

    func showFind(replace: Bool) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = replace ? NSTextFinder.Action.showReplaceInterface.rawValue : NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }
}

/// The word-processor surface: white paper regardless of app appearance, so it matches the PDF.
struct RichTextEditor: NSViewRepresentable {
    let text: NSAttributedString
    /// Bump to replace the content from outside (template change, revision reload).
    let revision: Int
    let isEditable: Bool
    @ObservedObject var controller: RichTextController

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var appliedRevision = -1

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated {
                parent.controller.onChange?(NSAttributedString(attributedString: textView.attributedString()))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.borderType = .noBorder
        scrollView.appearance = NSAppearance(named: .aqua)
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.insertionPointColor = .black
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.appearance = NSAppearance(named: .aqua)
        textView.typingAttributes = RichTextStyle(theme: controller.theme).bodyAttributes
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        controller.textView = textView
        textView.isEditable = isEditable
        if context.coordinator.appliedRevision != revision {
            context.coordinator.appliedRevision = revision
            textView.textStorage?.setAttributedString(text)
            textView.undoManager?.removeAllActions()
            textView.typingAttributes = RichTextStyle(theme: controller.theme).bodyAttributes
        }
    }
}

/// Formatting toolbar shown above the editor.
struct RichTextToolbar: View {
    @ObservedObject var controller: RichTextController
    let clauses: [Clause]
    /// Custom-field tokens (`field.key`, label) offered alongside the standard merge fields.
    var extraFields: [(String, String)] = []
    @State private var tableRows = 3
    @State private var tableColumns = 3
    @State private var showTablePicker = false

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Heading") { controller.apply(.heading1) }
                Button("Subheading") { controller.apply(.heading2) }
                Button("Body Text") { controller.apply(.body) }
            } label: {
                Label("Style", systemImage: "textformat.size")
            }
            .fixedSize()
            divider
            tool("bold", "Bold (⌘B)") { controller.toggle(.boldFontMask) }
            tool("italic", "Italic (⌘I)") { controller.toggle(.italicFontMask) }
            tool("underline", "Underline (⌘U)") { controller.toggleUnderline() }
            divider
            tool("list.bullet", "Bulleted list") { controller.toggleList(ordered: false) }
            tool("list.number", "Numbered list") { controller.toggleList(ordered: true) }
            Menu {
                Button("Align Left") { controller.align(.left) }
                Button("Centre") { controller.align(.center) }
                Button("Align Right") { controller.align(.right) }
                Button("Justify") { controller.align(.justified) }
            } label: {
                Image(systemName: "text.alignleft")
            }
            .fixedSize()
            .help("Alignment")
            divider
            Button { showTablePicker = true } label: { Image(systemName: "tablecells") }
                .buttonStyle(.borderless)
                .help("Insert table")
                .popover(isPresented: $showTablePicker) {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Rows: \(tableRows)", value: $tableRows, in: 2...30)
                        Stepper("Columns: \(tableColumns)", value: $tableColumns, in: 1...8)
                        Button("Insert Table") {
                            controller.insertTable(rows: tableRows, columns: tableColumns)
                            showTablePicker = false
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(16)
                    .frame(width: 220)
                }
            tool("photo", "Insert image") { controller.insertImage() }
            tool("doc.badge.plus", "Insert page break") { controller.insertPageBreak() }
            Menu {
                Button("Signature Block") { controller.insertSignatureBlock() }
                Button("Table of Contents") { controller.insertTableOfContents() }
                Divider()
                Menu("Clause") {
                    ForEach(ClauseLibrary.categories, id: \.self) { category in
                        let items = clauses.filter { $0.category == category }
                        if !items.isEmpty {
                            Section(category) {
                                ForEach(items) { clause in Button(clause.title) { controller.insertClause(clause) } }
                            }
                        }
                    }
                }
                Menu("Field") {
                    ForEach(MergeFields.all) { field in
                        Button(field.label) { controller.insertField(field.token) }
                    }
                    if !extraFields.isEmpty {
                        Divider()
                        ForEach(extraFields, id: \.0) { token, label in
                            Button(label) { controller.insertField(token) }
                        }
                    }
                }
            } label: {
                Label("Insert", systemImage: "plus.rectangle.on.rectangle")
            }
            .fixedSize()
            Spacer()
            tool("magnifyingglass", "Find & replace (⌘F)") { controller.showFind(replace: true) }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 18).padding(.horizontal, 2)
    }

    private func tool(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
