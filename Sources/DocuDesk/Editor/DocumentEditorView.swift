import DocuDeskCore
import SwiftUI

struct DocumentEditorView: View {
    let documentID: UUID
    @EnvironmentObject private var app: AppModel
    @State private var editor: DocumentEditorModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let editor {
                EditorContent(model: editor)
            } else if let loadError {
                VStack(spacing: 14) {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "This document can’t be opened", message: loadError)
                    Button("Back") { app.openDocumentID = nil }.buttonStyle(SecondaryButtonStyle())
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: load)
        .onDisappear { editor?.flushPendingSave() }
    }

    private func load() {
        guard editor == nil, let store = app.store else { return }
        do {
            let document = try store.loadDocument(id: documentID)
            let model = DocumentEditorModel(document: document, app: app)
            editor = model
            app.activeEditor = model
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct EditorContent: View {
    @ObservedObject var model: DocumentEditorModel
    @State private var confirmDelete = false
    @State private var showPayment = false
    @State private var showRevisions = false
    @State private var showBulk = false

    private var kind: DocumentKind { model.document.kind }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isLocked { lockedBanner }
            if !model.duplicates.isEmpty { duplicateBanner }
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 16) {
                            DetailsCard(model: model)
                            ClientCard(model: model)
                        }
                        .disabled(model.isLocked)
                        // The body editor manages its own read-only state so text stays selectable.
                        if model.document.customType?.fields.isEmpty == false {
                            CustomFieldsCard(model: model).disabled(model.isLocked)
                        }
                        if model.document.usesBody { BodyCard(model: model) }
                        VStack(spacing: 16) {
                            if model.document.usesLineItems {
                                ItemsCard(model: model)
                                if model.document.showsPricing { TaxTotalsCard(model: model) }
                            }
                            if kind == .receipt { ReceiptCard(model: model) }
                            if !model.document.usesBody || kind == .proposal || (model.document.customType?.showsPricing ?? false) {
                                NotesCard(model: model)
                            }
                        }
                        .disabled(model.isLocked)
                        // Payments, tags and history stay usable after issue.
                        if kind.acceptsPayments, model.document.status != .draft {
                            PaymentsCard(model: model, showPayment: $showPayment)
                        }
                        LinksCard(model: model, showRevisions: $showRevisions)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                }
                .frame(minWidth: 520, idealWidth: 640)

                previewPane
                    .frame(minWidth: 420, idealWidth: 520)
            }
        }
        .sheet(isPresented: $showPayment) { RecordPaymentSheet(model: model) }
        .sheet(isPresented: $showRevisions) { RevisionsSheet(model: model) }
        .sheet(isPresented: $showBulk) { BulkGenerateSheet(source: model.document) }
        .confirmationDialog("Move this draft to the Trash?", isPresented: $confirmDelete) {
            Button("Move to Trash", role: .destructive) { model.deleteDraft() }
        } message: {
            Text("\(model.document.number) will be moved to the macOS Trash, where you can still recover it.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Button { model.close() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(IconButtonStyle())
                .help("Back")
            KindBadge(kind: model.document.kind, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(model.document.number).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                    StatusPill(status: model.document.isOverdue ? .overdue : model.document.status)
                    if model.document.revision > 1 {
                        Text("R\(model.document.revision)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                HStack(spacing: 10) {
                    SaveIndicator(model: model)
                    TagEditor(tags: model.document.tags, suggestions: (try? model.store?.allTags()) ?? []) { model.setTags($0) }
                }
            }
            Spacer()
            Button { model.togglePinned() } label: {
                Image(systemName: model.document.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.document.pinned ? Color(hex: 0xF59E0B) : Theme.text)
            }
            .buttonStyle(IconButtonStyle())
            .help(model.document.pinned ? "Unpin" : "Pin to the top of lists")

            if model.document.status == .draft {
                Button { model.issue() } label: { Label("Issue", systemImage: "checkmark.seal") }
                    .buttonStyle(PrimaryButtonStyle())
                    .help("Lock the content and keep an issued snapshot")
            } else {
                Menu {
                    ForEach(model.document.statuses.filter { $0 != .draft }) { status in
                        Button(status.displayName) { model.setStatus(status) }
                    }
                } label: {
                    Text("Status: \(model.document.status.displayName)")
                }
                .menuStyle(.button)
                .fixedSize()
            }
            if kind.acceptsPayments, model.document.status.isOutstanding {
                Button { showPayment = true } label: { Label("Record Payment", systemImage: "indianrupeesign.circle") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button { model.exportPDF(choosingDestination: true) } label: { Label("Export PDF", systemImage: "arrow.down.doc") }
                .buttonStyle(SecondaryButtonStyle())
            Button { model.print() } label: { Image(systemName: "printer") }
                .buttonStyle(IconButtonStyle())
                .help("Print")
            Menu {
                Button("Export Word Document…") { model.exportDOCX(choosingDestination: true) }
                Button("Export Page Images (PNG)…") { model.exportPNG() }
                Divider()
                Button("Generate for Many Clients…") {
                    model.flushPendingSave()
                    showBulk = true
                }
                Button("Version History…") { showRevisions = true }
                Divider()
                Button("Duplicate") { model.duplicate() }
                if kind.convertsToInvoice {
                    Button("Convert to Invoice") { model.convertToInvoice() }
                }
                if model.isLocked {
                    Button("Create Revision") { model.createRevision() }
                }
                Divider()
                Button(model.document.archived ? "Unarchive" : "Archive") { model.toggleArchived() }
                Button("Show in Finder") { model.revealInFinder() }
                if model.document.status == .draft, model.document.revision == 1 {
                    Divider()
                    Button("Delete Draft…", role: .destructive) { confirmDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 34, height: 34)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
    }

    private var duplicateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text("This looks like a duplicate of \(model.duplicates.map(\.number).joined(separator: ", ")): same client and total within 30 days.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
            Spacer()
            if let first = model.duplicates.first {
                Button("Open \(first.number)") { model.app.openDocument(first.id) }.buttonStyle(.link)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 26)
        .padding(.bottom, 4)
    }

    private var lockedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
            Text("This \(model.document.typeName.lowercased()) has been issued, so its content is locked. Corrections go through a revision, which keeps the issued copy.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
            Spacer()
            Button("Create Revision") { model.createRevision() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 26)
        .padding(.bottom, 4)
    }

    private var previewPane: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Live Preview").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(model.pageCount) page\(model.pageCount == 1 ? "" : "s") · \(model.document.pageSize.displayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if model.usedFallbackTemplate {
                    Label("Template unavailable, using default", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                }
            }
            PagePreview(data: model.pdfData)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
        }
        .padding(18)
        .background(Theme.surfaceMuted)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

private struct SaveIndicator: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        Group {
            switch model.saveState {
            case .saved:
                Label(model.isLocked ? "Issued · read-only" : "Saved \(model.lastSaved.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")",
                      systemImage: model.isLocked ? "lock" : "checkmark.circle")
                    .foregroundStyle(model.isLocked ? Theme.secondary : Theme.success)
            case .pending:
                Label("Unsaved changes", systemImage: "circle.dashed").foregroundStyle(Theme.secondary)
            case .saving:
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(Theme.secondary)
            case let .failed(message):
                HStack(spacing: 6) {
                    Label("Save failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    Text(message).foregroundStyle(Theme.danger).lineLimit(1).help(message)
                    Button("Retry") { model.saveNow() }.buttonStyle(.link)
                }
            }
        }
        .font(.system(size: 12))
    }
}

// MARK: - Cards

private struct EditorCard<Content: View>: View {
    let title: String
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                content
            }
        }
    }
}

private struct DetailsCard: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        EditorCard(title: "Details", icon: "doc.text") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    LabeledField(label: model.document.numberLabel) {
                        TextField("Number", text: $model.document.number).fieldStyle()
                    }
                    LabeledField(label: "Title (optional)") {
                        TextField("e.g. Website redesign", text: $model.document.title).fieldStyle()
                    }
                }
                GridRow {
                    LabeledField(label: "Date") {
                        DatePicker("", selection: dateBinding(\.issueDate), displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                    if let label = model.document.dueDateLabel {
                        LabeledField(label: label) {
                            HStack {
                                Toggle("", isOn: hasDueDate).labelsHidden().toggleStyle(.checkbox)
                                if model.document.dueDate != nil {
                                    DatePicker("", selection: dueDateBinding, displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.field)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                GridRow {
                    LabeledField(label: model.document.kind == .purchaseOrder ? "Requisition / reference" : "Reference / PO number") {
                        TextField("Optional", text: $model.document.reference).fieldStyle()
                    }
                    LabeledField(label: "Place of supply") {
                        TextField("e.g. Maharashtra (27)", text: $model.document.placeOfSupply).fieldStyle()
                    }
                }
                GridRow {
                    LabeledField(label: "Currency") {
                        Picker("", selection: $model.document.currency) {
                            ForEach(CurrencyInfo.supported) { Text("\($0.code) · \($0.name)").tag($0.code) }
                        }
                        .labelsHidden()
                    }
                    LabeledField(label: "Paper") {
                        HStack {
                            Picker("", selection: $model.document.pageSize) {
                                ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            Picker("", selection: $model.document.orientation) {
                                ForEach(PageOrientation.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            LabeledField(label: "Template") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.templateChoices, id: \.id) { choice in
                            Button(choice.name) { model.applyTemplate(id: choice.id) }
                                .buttonStyle(ChipButtonStyle(selected: choice.id == model.document.templateID))
                        }
                    }
                }
            }
        }
    }

    private func dateBinding(_ keyPath: WritableKeyPath<DocumentRecord, CalendarDate>) -> Binding<Date> {
        Binding(get: { model.document[keyPath: keyPath].date }, set: { model.document[keyPath: keyPath] = CalendarDate($0) })
    }

    private var dueDateBinding: Binding<Date> {
        Binding(get: { (model.document.dueDate ?? model.document.issueDate).date }, set: { model.document.dueDate = CalendarDate($0) })
    }

    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { model.document.dueDate != nil },
            set: { enabled in
                model.document.dueDate = enabled
                    ? model.document.issueDate.adding(days: model.document.defaultDueDays(model.document.company) ?? 15)
                    : nil
            }
        )
    }
}

private struct ClientCard: View {
    @ObservedObject var model: DocumentEditorModel
    @State private var showShipping = false

    var body: some View {
        EditorCard(title: model.document.partyLabel, icon: "person.crop.rectangle") {
            HStack {
                Menu {
                    if model.customers.isEmpty {
                        Text("No saved clients yet")
                    }
                    ForEach(model.customers) { customer in
                        Button(customer.name) { model.applyCustomer(customer) }
                    }
                } label: {
                    Label(linkedName ?? "Choose a saved client", systemImage: "person.2")
                }
                .menuStyle(.button)
                .fixedSize()
                Spacer()
                if model.document.customerID == nil, !model.document.customer.isEmpty {
                    Button("Save as Client") { model.saveCustomerFromDocument() }
                        .buttonStyle(.link)
                        .font(.system(size: 12.5))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    LabeledField(label: "Name") { TextField("Client or company name", text: $model.document.customer.name).fieldStyle() }
                    LabeledField(label: "Contact person") { TextField("Optional", text: $model.document.customer.contactPerson).fieldStyle() }
                }
                GridRow {
                    LabeledField(label: "Email") { TextField("Optional", text: $model.document.customer.email).fieldStyle() }
                    LabeledField(label: "Phone") { TextField("Optional", text: $model.document.customer.phone).fieldStyle() }
                }
            }
            AddressFields(title: "Billing address", address: $model.document.customer.billingAddress)
            LabeledField(label: "\(model.document.company.taxIDLabel) / tax ID") {
                TextField("Optional", text: $model.document.customer.taxID).fieldStyle()
            }
            DisclosureGroup("Different shipping address", isExpanded: $showShipping) {
                AddressFields(title: "", address: $model.document.customer.shippingAddress).padding(.top, 8)
            }
            .font(.system(size: 12.5))
            .onAppear { showShipping = !model.document.customer.shippingAddress.isEmpty }
        }
    }

    private var linkedName: String? {
        model.document.customerID.flatMap { id in model.customers.first { $0.id == id }?.name }
    }
}

struct AddressFields: View {
    let title: String
    @Binding var address: Address

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            TextField("Address line 1", text: $address.line1).fieldStyle()
            TextField("Address line 2", text: $address.line2).fieldStyle()
            HStack(spacing: 8) {
                TextField("City", text: $address.city).fieldStyle()
                TextField("State", text: $address.state).fieldStyle()
                TextField("PIN / ZIP", text: $address.postalCode).fieldStyle().frame(width: 100)
            }
            TextField("Country", text: $address.country).fieldStyle()
        }
    }
}

private struct ItemsCard: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        EditorCard(title: model.document.kind == .deliveryChallan ? "Goods" : "Line Items", icon: "list.bullet.rectangle") {
            LineItemsEditor(model: model)
            HStack(spacing: 10) {
                Button { model.addItem() } label: { Label("Add Item", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
                Menu {
                    if model.products.isEmpty { Text("No products or services saved yet") }
                    ForEach(model.products) { product in
                        Button("\(product.name) · \(MoneyFormatter.compact(product.price, currency: model.document.currency))") {
                            model.addProduct(product)
                        }
                    }
                } label: {
                    Label("Add from Catalog", systemImage: "cart")
                }
                .menuStyle(.button)
                .fixedSize()
                Spacer()
            }
        }
    }
}

private struct TaxTotalsCard: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        let totals = model.totals
        let currency = model.document.currency
        EditorCard(title: "Tax & Totals", icon: "percent") {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "Tax") {
                        Picker("", selection: $model.document.taxSplit) {
                            ForEach(TaxSplit.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                    }
                    if model.document.taxSplit != .none {
                        LabeledField(label: "Pricing") {
                            Picker("", selection: $model.document.taxMode) {
                                ForEach(TaxMode.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    if model.document.taxSplit == .single {
                        LabeledField(label: "Tax label") { TextField("VAT", text: $model.document.taxLabel).fieldStyle() }
                    }
                    LabeledField(label: "Discount on total") {
                        HStack(spacing: 6) {
                            DecimalField(placeholder: "0", value: $model.document.documentDiscountValue).fieldStyle()
                            Picker("", selection: $model.document.documentDiscountKind) {
                                Text("%").tag(DiscountKind.percent)
                                Text(currency).tag(DiscountKind.amount)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 110)
                        }
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "Shipping") { DecimalField(placeholder: "0", value: $model.document.shipping).fieldStyle() }
                        LabeledField(label: "Advance received") { DecimalField(placeholder: "0", value: $model.document.advancePaid).fieldStyle() }
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "Adjustment label") { TextField("Adjustment", text: $model.document.adjustmentLabel).fieldStyle() }
                        LabeledField(label: "Adjustment (±)") { DecimalField(placeholder: "0", value: $model.document.adjustment).fieldStyle() }
                    }
                    Toggle("Round total to nearest whole unit", isOn: $model.document.roundOffTotal)
                        .font(.system(size: 12.5))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    TotalRow(label: "Subtotal", value: MoneyFormatter.format(totals.subtotal, currency: currency))
                    if totals.documentDiscount > 0 {
                        TotalRow(label: "Discount", value: "−" + MoneyFormatter.format(totals.documentDiscount, currency: currency))
                    }
                    if !totals.taxLines.isEmpty {
                        TotalRow(label: "Taxable value", value: MoneyFormatter.format(totals.taxableAmount, currency: currency))
                    }
                    ForEach(totals.taxLines, id: \.label) { tax in
                        TotalRow(label: tax.label, value: MoneyFormatter.format(tax.amount, currency: currency))
                    }
                    if totals.shipping != 0 { TotalRow(label: "Shipping", value: MoneyFormatter.format(totals.shipping, currency: currency)) }
                    if totals.adjustment != 0 { TotalRow(label: model.document.adjustmentLabel, value: MoneyFormatter.format(totals.adjustment, currency: currency)) }
                    if totals.roundOff != 0 { TotalRow(label: "Round off", value: MoneyFormatter.format(totals.roundOff, currency: currency)) }
                    Divider()
                    HStack {
                        Text("Total").font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text(MoneyFormatter.format(totals.grandTotal, currency: currency))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                    if totals.advancePaid > 0 {
                        TotalRow(label: "Balance due", value: MoneyFormatter.format(totals.balanceDue, currency: currency), bold: true)
                    }
                    Text(totals.amountInWords)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .padding(14)
                .frame(width: 270)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct TotalRow: View {
    let label: String
    let value: String
    var bold = false

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).foregroundStyle(Theme.text).monospacedDigit()
        }
        .font(.system(size: 12.5, weight: bold ? .semibold : .regular))
    }
}

private struct ReceiptCard: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        EditorCard(title: "Payment", icon: "indianrupeesign.circle") {
            if model.document.receipt != nil {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        LabeledField(label: "Amount received") {
                            DecimalField(placeholder: "0", value: receiptBinding(\.amountReceived)).fieldStyle()
                        }
                        LabeledField(label: "Method") {
                            Picker("", selection: receiptBinding(\.method)) {
                                ForEach(PaymentMethod.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                    GridRow {
                        LabeledField(label: "Transaction reference") {
                            TextField("UTR / cheque no.", text: receiptBinding(\.transactionReference)).fieldStyle()
                        }
                        LabeledField(label: "Against invoice") {
                            TextField("Invoice number", text: receiptBinding(\.againstDocumentNumber)).fieldStyle()
                        }
                    }
                }
                LabeledField(label: "Purpose (optional)") {
                    TextField("e.g. Advance for website project", text: receiptBinding(\.purpose)).fieldStyle()
                }
                Text(model.totals.amountInWords).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func receiptBinding<T>(_ keyPath: WritableKeyPath<ReceiptDetails, T>) -> Binding<T> {
        Binding(
            get: { (model.document.receipt ?? ReceiptDetails())[keyPath: keyPath] },
            set: { value in
                var receipt = model.document.receipt ?? ReceiptDetails()
                receipt[keyPath: keyPath] = value
                model.document.receipt = receipt
            }
        )
    }
}

private struct NotesCard: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        EditorCard(title: "Notes & Terms", icon: "text.alignleft") {
            if model.document.showsPricing, model.document.kind != .receipt {
                NoteEditor(label: "Payment details", text: $model.document.paymentDetails)
            }
            NoteEditor(label: "Notes", text: $model.document.notes)
            NoteEditor(label: "Terms & conditions", text: $model.document.terms, height: 90)
            Menu {
                ForEach(ClauseLibrary.categories, id: \.self) { category in
                    let items = model.clauses.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category) {
                            ForEach(items) { clause in Button(clause.title) { model.appendClauseToTerms(clause) } }
                        }
                    }
                }
            } label: {
                Label("Add a Saved Clause", systemImage: "text.badge.plus")
            }
            .fixedSize()
        }
    }
}

struct NoteEditor: View {
    let label: String
    @Binding var text: String
    var height: CGFloat = 60

    var body: some View {
        LabeledField(label: label) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: height)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
        }
    }
}

private struct LinksCard: View {
    @ObservedObject var model: DocumentEditorModel
    @Binding var showRevisions: Bool

    var body: some View {
        let versions = model.revisionCount
        if !model.document.links.isEmpty || !model.document.exports.isEmpty || versions > 0 {
            EditorCard(title: "History", icon: "clock.arrow.circlepath") {
                if versions > 0 {
                    HStack {
                        Text("\(versions) earlier version\(versions == 1 ? "" : "s") saved").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("Compare & Restore…") { showRevisions = true }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                ForEach(model.document.links, id: \.self) { link in
                    HStack {
                        Text(link.kind.displayName).foregroundStyle(Theme.secondary)
                        Button(link.number) { model.app.openDocument(link.documentID) }.buttonStyle(.link)
                        Spacer()
                    }
                    .font(.system(size: 12.5))
                }
                ForEach(Array(model.document.exports.suffix(5).reversed().enumerated()), id: \.offset) { _, export in
                    HStack {
                        Image(systemName: "doc.richtext").foregroundStyle(Theme.secondary)
                        Text(URL(fileURLWithPath: export.path).lastPathComponent)
                        Spacer()
                        Text(export.exportedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}
