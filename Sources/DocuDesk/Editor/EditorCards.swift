import DocuDeskCore
import SwiftUI

/// Word-processor body for proposals, agreements, letters and reports.
struct BodyCard: View {
    @ObservedObject var model: DocumentEditorModel
    @State private var showDraft = false

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Content", systemImage: "doc.richtext")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("Fields like {{client.name}} are filled in when the PDF is made.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
                if !model.isLocked {
                    HStack(spacing: 8) {
                        RichTextToolbar(controller: model.richText, clauses: model.clauses,
                                        extraFields: (model.document.customType?.fields ?? []).map { ("field.\($0.id)", $0.label) })
                        AIMenu(model: model, showDraft: $showDraft)
                    }
                }
                RichTextEditor(text: model.editorBody, revision: model.bodyRevision, isEditable: !model.isLocked, controller: model.richText)
                    .frame(height: 560)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
            }
        }
        .sheet(isPresented: $showDraft) { AIDraftSheet(model: model) }
    }
}

struct PaymentsCard: View {
    @ObservedObject var model: DocumentEditorModel
    @Binding var showPayment: Bool
    @State private var pendingDelete: PaymentRecord?

    var body: some View {
        let totals = model.totals
        let currency = model.document.currency
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Payments", systemImage: "indianrupeesign.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if model.document.status.isOutstanding {
                        Button { showPayment = true } label: { Label("Record Payment", systemImage: "plus") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                HStack(spacing: 12) {
                    summary("Total", MoneyFormatter.format(totals.grandTotal, currency: currency), Theme.text)
                    summary("Paid", MoneyFormatter.format(totals.amountPaid + totals.advancePaid, currency: currency), Theme.success)
                    summary("Balance due", MoneyFormatter.format(totals.balanceDue, currency: currency), totals.balanceDue > 0 ? Theme.warning : Theme.success)
                }
                if model.document.payments.isEmpty {
                    Text("No payments recorded yet. Recording a payment updates the status and can issue a receipt.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.document.payments) { payment in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(payment.date.display) · \(payment.method.displayName)").font(.system(size: 12.5, weight: .medium))
                                    let details = [payment.reference, payment.note].filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !details.isEmpty {
                                        Text(details).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    }
                                }
                                Spacer()
                                if let receiptID = payment.receiptID, let number = payment.receiptNumber {
                                    Button(number) { model.app.openDocument(receiptID) }.buttonStyle(.link).font(.system(size: 12))
                                }
                                Text(MoneyFormatter.format(payment.amount, currency: currency))
                                    .font(.system(size: 13, weight: .semibold))
                                    .monospacedDigit()
                                Button { pendingDelete = payment } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Remove this payment")
                            }
                            .padding(.vertical, 8)
                            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Remove this payment?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Remove Payment", role: .destructive) {
                if let payment = pendingDelete { model.deletePayment(payment.id) }
            }
        } message: {
            Text("The balance and status are recalculated. A receipt issued for this payment is marked cancelled, not deleted.")
        }
    }

    private func summary(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(color).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RecordPaymentSheet: View {
    @ObservedObject var model: DocumentEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var method: PaymentMethod = .bankTransfer
    @State private var reference = ""
    @State private var note = ""
    @State private var createReceipt = true

    var body: some View {
        let balance = model.totals.balanceDue
        VStack(alignment: .leading, spacing: 16) {
            Text("Record Payment").font(.system(size: 18, weight: .bold))
            Text("\(model.document.number) · balance due \(MoneyFormatter.format(balance, currency: model.document.currency))")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 12) {
                LabeledField(label: "Amount") { DecimalField(placeholder: "0.00", value: $amount).fieldStyle() }
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                }
            }
            HStack(spacing: 12) {
                LabeledField(label: "Method") {
                    Picker("", selection: $method) {
                        ForEach(PaymentMethod.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                }
                LabeledField(label: "Reference") { TextField("UTR / cheque no.", text: $reference).fieldStyle() }
            }
            LabeledField(label: "Note") { TextField("Optional", text: $note).fieldStyle() }
            Toggle("Issue a payment receipt", isOn: $createReceipt)
                .font(.system(size: 12.5))
            HStack {
                Button("Pay in Full") { amount = balance }.buttonStyle(.link)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Record") {
                    let payment = PaymentRecord(date: CalendarDate(date), amount: amount, method: method, reference: reference, note: note)
                    if model.recordPayment(payment, createReceipt: createReceipt) { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amount <= 0 || amount > balance)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { amount = balance }
    }
}

/// Inline tag chips with an add field. Tags are metadata, so they work on issued documents too.
struct TagEditor: View {
    let tags: [String]
    let suggestions: [String]
    let onChange: ([String]) -> Void
    @State private var adding = false
    @State private var newTag = ""

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text(tag)
                    Button { onChange(tags.filter { $0 != tag }) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.accentSoft, in: Capsule())
            }
            Button { adding = true } label: {
                Label(tags.isEmpty ? "Add tag" : "", systemImage: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $adding) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("New tag", text: $newTag)
                        .fieldStyle()
                        .onSubmit(add)
                    let options = suggestions.filter { option in !tags.contains { $0.caseInsensitiveCompare(option) == .orderedSame } }
                    if !options.isEmpty {
                        Text("Existing tags").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        ForEach(options.prefix(8), id: \.self) { option in
                            Button(option) {
                                onChange(tags + [option])
                                adding = false
                            }
                            .buttonStyle(.link)
                        }
                    }
                    Text("Suggested: Client, Internal, Urgent, Tax").font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                }
                .padding(14)
                .frame(width: 220)
            }
        }
    }

    private func add() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        onChange(tags + [tag])
        newTag = ""
        adding = false
    }
}
