import AppKit
import DocuDeskCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum SaveState: Equatable {
    case saved
    case pending
    case saving
    case failed(String)
}

@MainActor
final class DocumentEditorModel: ObservableObject {
    @Published var document: DocumentRecord {
        didSet {
            guard !replacing, document != oldValue else { return }
            documentChanged()
        }
    }
    @Published private(set) var saveState: SaveState = .saved
    @Published private(set) var lastSaved: Date?
    @Published private(set) var pdfData: Data?
    @Published private(set) var pageCount = 1
    @Published private(set) var usedFallbackTemplate = false
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var products: [ProductService] = []
    @Published private(set) var clauses: [Clause] = []
    @Published private(set) var customTemplates: [CustomTemplate] = []
    @Published private(set) var duplicates: [DocumentSummary] = []
    /// Body shown in the rich-text editor; replaced (with `bodyRevision` bumped) only from outside.
    @Published private(set) var editorBody = NSAttributedString()
    @Published private(set) var bodyRevision = 0
    @Published private(set) var revisionCount = 0

    let app: AppModel
    let richText: RichTextController
    private var replacing = false
    private var saveTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var bodyTask: Task<Void, Never>?
    private var pendingBody: NSAttributedString?

    init(document: DocumentRecord, app: AppModel) {
        self.document = document
        self.app = app
        richText = RichTextController(theme: app.store?.theme(for: document) ?? TemplateLibrary.theme(for: .modern))
        lastSaved = document.updatedAt
        editorBody = document.body.attributedString()
        richText.onChange = { [weak self] text in self?.bodyEdited(text) }
        reloadLookups()
        refreshDuplicates()
        refreshRevisionCount()
        renderPreview(immediately: true)
    }

    var store: WorkspaceStore? { app.store }
    var isLocked: Bool { document.status.isContentLocked }
    var totals: DocumentTotals { DocumentCalculator.totals(for: document) }
    var logo: NSImage? { store?.image(at: document.company.logoPath) }
    var theme: TemplateTheme { store?.theme(for: document) ?? TemplateLibrary.theme(for: .modern) }

    func reloadLookups() {
        customers = (try? store?.customers()) ?? []
        products = (try? store?.products()) ?? []
        clauses = (try? store?.clauses()) ?? []
        customTemplates = (try? store?.customTemplates()) ?? []
    }

    func refreshRevisionCount() {
        revisionCount = (try? store?.revisions(of: document.id).count) ?? 0
    }

    func revisions() -> [RevisionSnapshot] {
        (try? store?.revisions(of: document.id)) ?? []
    }

    func restore(_ snapshot: RevisionSnapshot) {
        perform("Couldn’t restore that version") { store in
            try store.restoreRevision(snapshot, into: document.id)
            reload()
            app.refresh()
            app.flash("Restored. The replaced version is kept in the history.")
        }
    }

    func exportPNG() {
        guard let folder = StorageLocation.chooseFolder(message: "Choose a folder for the page images", prompt: "Export") else { return }
        perform("Image export failed") { store in
            let urls = try store.exportPNG(document, to: folder)
            app.flash("Exported \(urls.count) image\(urls.count == 1 ? "" : "s")")
            app.revealInFinder(urls.first ?? folder)
        }
    }

    func refreshDuplicates() {
        guard document.status == .draft, document.showsPricing else {
            duplicates = []
            return
        }
        duplicates = (try? store?.possibleDuplicates(of: document)) ?? []
    }

    // MARK: Rich-text body

    /// Serialising RTFD on every keystroke is wasteful, so edits are batched briefly.
    private func bodyEdited(_ text: NSAttributedString) {
        guard !isLocked else { return }
        pendingBody = text
        saveState = .pending
        bodyTask?.cancel()
        bodyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.commitPendingBody()
        }
    }

    private func commitPendingBody() {
        bodyTask?.cancel()
        guard let pendingBody else { return }
        self.pendingBody = nil
        document.body = RichTextBody(attributed: pendingBody)
    }

    private func replaceEditorBody(_ text: NSAttributedString) {
        editorBody = text
        bodyRevision += 1
    }

    // MARK: Saving

    private func documentChanged() {
        renderPreview()
        guard !isLocked else { return }
        saveState = .pending
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes immediately. "Saved" is shown only after the file and index writes succeed.
    func saveNow() {
        saveTask?.cancel()
        guard let store, saveState != .saved else { return }
        saveState = .saving
        do {
            let saved = try store.save(document)
            replace(with: saved)
            saveState = .saved
            lastSaved = Date()
            refreshDuplicates()
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    func flushPendingSave() {
        commitPendingBody()
        if saveState == .pending || saveState == .saving { saveNow() }
    }

    private func replace(with document: DocumentRecord) {
        replacing = true
        self.document = document
        replacing = false
    }

    private func reload() {
        guard let store, let fresh = try? store.loadDocument(id: document.id) else { return }
        replace(with: fresh)
        saveState = .saved
        refreshRevisionCount()
        richText.theme = theme
        if fresh.body.attributedString().string != editorBody.string || bodyRevision == 0 {
            replaceEditorBody(fresh.body.attributedString())
        }
        renderPreview(immediately: true)
    }

    // MARK: Preview

    func renderPreview(immediately: Bool = false) {
        previewTask?.cancel()
        let snapshot = document
        let logo = logo
        let theme = theme
        let missing = store?.templateIsMissing(for: document) ?? false
        previewTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) { DocumentRenderer.render(snapshot, logo: logo, theme: theme) }.value
            let output = DocumentRenderer.Output(data: rendered.data, pageCount: rendered.pageCount, usedFallbackTemplate: missing)
            guard !Task.isCancelled, let self else { return }
            self.pdfData = output.data
            self.pageCount = output.pageCount
            self.usedFallbackTemplate = output.usedFallbackTemplate
        }
    }

    // MARK: Line items and parties

    func addItem() {
        document.items.append(LineItem(name: "", quantity: 1, unitPrice: 0, taxRate: document.company.defaultTaxRate))
    }

    func addProduct(_ product: ProductService) {
        let item = LineItem(product: product, fallbackTaxRate: document.company.defaultTaxRate)
        if let index = document.items.firstIndex(where: { $0.name.isEmpty && $0.unitPrice == 0 }) {
            document.items[index] = item
        } else {
            document.items.append(item)
        }
    }

    func removeItem(_ id: UUID) {
        document.items.removeAll { $0.id == id }
    }

    func moveItem(_ id: UUID, by offset: Int) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard document.items.indices.contains(target) else { return }
        document.items.swapAt(index, target)
    }

    func applyCustomer(_ customer: Customer) {
        guard let store else { return }
        var copy = document
        store.apply(customer: customer, to: &copy)
        document = copy
    }

    /// Saves typed-in client details as a reusable record and links it.
    func saveCustomerFromDocument() {
        guard let store, !document.customer.isEmpty else { return }
        let customer = Customer(party: document.customer)
        do {
            try store.saveCustomer(customer)
            document.customerID = customer.id
            reloadLookups()
            app.flash("Saved \(customer.name) to Clients")
        } catch {
            app.show(error)
        }
    }

    /// Switches template. Text documents have their body restyled into the new template's fonts.
    func applyTemplate(id: String) {
        guard let store, let definition = try? store.templateDefinition(id: id, kind: document.kind) else { return }
        commitPendingBody()
        let oldTheme = theme
        var updated = document
        updated.templateID = definition.id
        updated.templateVersion = definition.version
        let newTheme = store.theme(for: updated)
        if document.usesBody {
            let restyled = RichTextTransform.restyle(document.body.attributedString(), from: oldTheme, to: newTheme)
            updated.body = RichTextBody(attributed: restyled)
            richText.theme = newTheme
            replaceEditorBody(restyled)
        }
        document = updated
    }

    var templateChoices: [(id: String, name: String)] {
        TemplateLibrary.templates(for: document.kind).map { ($0.id, $0.style.displayName) }
            + customTemplates.map { ($0.templateID, $0.name) }
    }

    // MARK: Payments, tags and organisation (allowed on issued documents)

    func recordPayment(_ payment: PaymentRecord, createReceipt: Bool) -> Bool {
        guard let store else { return false }
        flushPendingSave()
        do {
            let result = try store.recordPayment(payment, toInvoice: document.id, createReceipt: createReceipt)
            reload()
            app.refresh()
            app.flash(result.receipt.map { "Payment recorded · receipt \($0.number) issued" } ?? "Payment recorded")
            return true
        } catch {
            app.show(error, title: "Couldn’t record the payment")
            return false
        }
    }

    func deletePayment(_ id: UUID) {
        perform("Couldn’t remove the payment") { store in
            try store.deletePayment(id, fromInvoice: document.id)
            reload()
            app.refresh()
        }
    }

    func setTags(_ tags: [String]) {
        perform("Couldn’t update tags") { store in
            try store.setTags(tags, for: [document.id])
            reload()
            app.refresh()
        }
    }

    func togglePinned() {
        perform("Couldn’t pin") { store in
            try store.setPinned(!document.pinned, for: [document.id])
            reload()
            app.refresh()
        }
    }

    func toggleArchived() {
        perform("Couldn’t archive") { store in
            try store.setArchived(!document.archived, for: [document.id])
            reload()
            app.refresh()
            app.flash(document.archived ? "Archived. Find it with the Archived filter." : "Restored from the archive")
        }
    }

    /// Appends a clause to the terms of a line-item document.
    func appendClauseToTerms(_ clause: Clause) {
        let text = clause.text.replacingOccurrences(of: "**", with: "")
        document.terms = document.terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : document.terms + "\n" + text
    }

    // MARK: Lifecycle

    private func perform(_ title: String, _ action: (WorkspaceStore) throws -> Void) {
        guard let store else { return }
        flushPendingSave()
        if case let .failed(message) = saveState {
            app.alert = AppAlert(title: title, message: "Fix the save problem first: \(message)")
            return
        }
        do {
            try action(store)
        } catch {
            app.show(error, title: title)
        }
    }

    func issue() {
        perform("Couldn’t issue the document") { store in
            try store.issue(document)
            reload()
            app.flash("\(document.number) issued and locked")
        }
    }

    func setStatus(_ status: DocumentStatus) {
        perform("Couldn’t change the status") { store in
            try store.setStatus(status, for: document.id)
            reload()
        }
    }

    func createRevision() {
        perform("Couldn’t create a revision") { store in
            try store.createRevision(of: document.id)
            reload()
            app.flash("Revision R\(document.revision) created. The previous version is kept.")
        }
    }

    func duplicate() {
        perform("Couldn’t duplicate") { store in
            let copy = try store.duplicate(document.id)
            app.refresh()
            app.openDocument(copy.id)
        }
    }

    func convertToInvoice() {
        perform("Couldn’t convert") { store in
            let invoice = try store.convertToInvoice(document.id)
            app.refresh()
            app.openDocument(invoice.id)
        }
    }

    func deleteDraft() {
        perform("Couldn’t delete") { store in
            try store.deleteDraft(id: document.id)
            app.navigate(to: app.screen)
            app.refresh()
            app.flash("Draft moved to the Trash")
        }
    }

    func close() {
        flushPendingSave()
        app.openDocumentID = nil
        app.refresh()
    }

    // MARK: Output

    /// Always writes the PDF into the document's own folder; optionally also saves a copy elsewhere.
    func exportPDF(choosingDestination: Bool) {
        perform("Export failed") { store in
            let result = try store.exportPDF(document)
            replace(with: result.document)
            app.refresh()
            guard choosingDestination else {
                app.revealInFinder(result.url)
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = result.url.lastPathComponent
            panel.canCreateDirectories = true
            panel.message = "A copy is also kept in the document’s folder."
            guard panel.runModal() == .OK, let destination = panel.url else {
                app.flash("PDF saved in the document folder")
                return
            }
            if destination.standardizedFileURL != result.url.standardizedFileURL {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: result.url, to: destination)
            }
            app.flash("Exported \(destination.lastPathComponent)")
        }
    }

    /// Writes a Word copy into the document's folder, optionally also saving it elsewhere.
    func exportDOCX(choosingDestination: Bool) {
        perform("Word export failed") { store in
            let url = try store.exportDOCX(document)
            guard choosingDestination else {
                app.revealInFinder(url)
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
            panel.nameFieldStringValue = url.lastPathComponent
            panel.message = "A copy is also kept in the document’s folder."
            guard panel.runModal() == .OK, let destination = panel.url else {
                app.flash("Word file saved in the document folder")
                return
            }
            if destination.standardizedFileURL != url.standardizedFileURL {
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: url, to: destination)
            }
            app.flash("Exported \(destination.lastPathComponent)")
        }
    }

    func print() {
        let data = DocumentRenderer.pdfData(for: document, logo: logo, theme: theme)
        guard let pdf = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        operation.jobTitle = "\(document.typeName) \(document.number)"
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    func revealInFinder() {
        guard let folder = try? store?.documentFolder(for: document.id) else { return }
        app.revealInFinder(folder)
    }
}
