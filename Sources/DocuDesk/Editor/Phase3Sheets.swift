import AppKit
import DocuDeskCore
import SwiftUI

// MARK: - Custom fields

struct CustomFieldsCard: View {
    @ObservedObject var model: DocumentEditorModel

    var body: some View {
        let fields = model.document.customType?.fields ?? []
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("\(model.document.typeName) Details", systemImage: "list.bullet.rectangle.portrait")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(fields) { field in
                        LabeledField(label: field.label + (field.required ? " *" : "")) {
                            editor(for: field)
                        }
                    }
                }
                if !model.document.missingRequiredFields.isEmpty, model.document.status == .draft {
                    Text("Required before issuing: \(model.document.missingRequiredFields.joined(separator: ", "))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { model.document.customFields[key] ?? "" }, set: { model.document.customFields[key] = $0 })
    }

    @ViewBuilder
    private func editor(for field: CustomFieldDefinition) -> some View {
        switch field.type {
        case .text:
            TextField(field.label, text: binding(field.id)).fieldStyle()
        case .number:
            TextField("0", text: binding(field.id)).fieldStyle().multilineTextAlignment(.trailing)
        case .multiline:
            TextEditor(text: binding(field.id))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
        case .date:
            HStack {
                DatePicker("", selection: Binding(
                    get: { CalendarDate(iso: model.document.customFields[field.id] ?? "")?.date ?? Date() },
                    set: { model.document.customFields[field.id] = CalendarDate($0).iso }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                if (model.document.customFields[field.id] ?? "").isEmpty {
                    Text("Not set").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
            }
        case .choice:
            Picker("", selection: binding(field.id)) {
                Text("Choose…").tag("")
                ForEach(field.choices, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        case .checkbox:
            Toggle("", isOn: Binding(
                get: { model.document.customFields[field.id] == "true" },
                set: { model.document.customFields[field.id] = $0 ? "true" : "false" }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
        }
    }
}

// MARK: - Version history

struct RevisionsSheet: View {
    @ObservedObject var model: DocumentEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [RevisionSnapshot] = []
    @State private var selection: String?
    @State private var confirmRestore = false

    private var selected: RevisionSnapshot? { snapshots.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Version History").font(.system(size: 19, weight: .bold))
                    Text("Compare an earlier version with the current one, or bring it back. Nothing is overwritten: the current version is kept too.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 16) {
                List(selection: $selection) {
                    ForEach(snapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("R\(snapshot.revision) · \(snapshot.label)").font(.system(size: 13, weight: .medium))
                            Text(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            Text(MoneyFormatter.format(DocumentCalculator.totals(for: snapshot.document).grandTotal, currency: snapshot.document.currency))
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(snapshot.id)
                    }
                }
                .frame(width: 240)
                .overlay {
                    if snapshots.isEmpty {
                        Text("No earlier versions yet. Versions are kept when a document is issued, revised or restored.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).padding()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let selected {
                        let entries = DocumentComparer.compare(selected.document, model.document)
                        HStack {
                            Text("Changes from R\(selected.revision) to the current version").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Button("Restore This Version…") { confirmRestore = true }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(entries.isEmpty)
                        }
                        if entries.isEmpty {
                            EmptyStateView(icon: "equal.circle", title: "No differences", message: "This version matches the current document.")
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(entries) { entry in DiffRow(entry: entry) }
                                }
                            }
                        }
                    } else {
                        EmptyStateView(icon: "clock.arrow.circlepath", title: "Choose a version", message: "Select a version on the left to see what changed.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(24)
        .frame(width: 920, height: 620)
        .onAppear {
            snapshots = model.revisions()
            selection = snapshots.first?.id
        }
        .confirmationDialog("Restore this version?", isPresented: $confirmRestore) {
            Button("Restore") {
                if let selected {
                    model.restore(selected)
                    dismiss()
                }
            }
        } message: {
            Text(model.isLocked
                 ? "The document is issued, so restoring creates a new revision. The issued copy stays in the history."
                 : "The current draft is saved in the history before the older content is brought back.")
        }
    }
}

private struct DiffRow: View {
    let entry: DiffEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.change.rawValue.capitalized)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(entry.section) · \(entry.field)").font(.system(size: 12, weight: .semibold))
                if !entry.old.isEmpty {
                    Text(entry.old).font(.system(size: 12)).strikethrough(entry.change != .added).foregroundStyle(Theme.danger.opacity(0.85))
                }
                if !entry.new.isEmpty {
                    Text(entry.new).font(.system(size: 12)).foregroundStyle(Theme.success)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var color: Color {
        switch entry.change {
        case .added: Theme.success
        case .removed: Theme.danger
        case .changed: Theme.warning
        }
    }
}

// MARK: - Bulk generation

struct BulkGenerateSheet: View {
    let source: DocumentRecord
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable, Identifiable {
        case clients = "Saved Clients"
        case csv = "CSV File"
        var id: String { rawValue }
    }

    @State private var mode: Source = .clients
    @State private var customers: [Customer] = []
    @State private var chosen: Set<UUID> = []
    @State private var csvRecipients: [BulkRecipient] = []
    @State private var csvColumns: [String] = []
    @State private var csvName = ""
    @State private var issueDate = Date()
    @State private var issue = false
    @State private var exportFolder: URL?
    @State private var saveNewClients = true
    @State private var running = false
    @State private var progress: Double = 0
    @State private var result: BulkResult?

    private var recipients: [BulkRecipient] {
        switch mode {
        case .clients: customers.filter { chosen.contains($0.id) }.map(BulkRecipient.init(customer:))
        case .csv: csvRecipients
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Generate for Many Clients").font(.system(size: 19, weight: .bold))
                Text("Creates one copy of \(source.number) per recipient with its own number. Items, text and settings are copied; client details and {{field.…}} values change per copy.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
            if let result {
                resultView(result)
            } else {
                Picker("", selection: $mode) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
                Group {
                    switch mode {
                    case .clients: clientPicker
                    case .csv: csvPicker
                    }
                }
                .frame(height: 260)
                options
                HStack {
                    if running {
                        ProgressView(value: progress).frame(width: 220)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction).disabled(running)
                    Button("Generate \(recipients.count) Document\(recipients.count == 1 ? "" : "s")") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(recipients.isEmpty || running)
                }
            }
        }
        .padding(24)
        .frame(width: 640)
        .onAppear { customers = (try? app.store?.customers()) ?? [] }
    }

    private var clientPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(chosen.count) of \(customers.count) selected").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                Button(chosen.count == customers.count ? "Select None" : "Select All") {
                    chosen = chosen.count == customers.count ? [] : Set(customers.map(\.id))
                }
                .buttonStyle(.link)
            }
            List(customers) { customer in
                Toggle(isOn: Binding(get: { chosen.contains(customer.id) }, set: { on in
                    if on { chosen.insert(customer.id) } else { chosen.remove(customer.id) }
                })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(customer.name).font(.system(size: 13))
                        if !customer.email.isEmpty { Text(customer.email).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var csvPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Choose CSV…") { chooseCSV() }.buttonStyle(SecondaryButtonStyle())
                Text(csvName.isEmpty ? "No file chosen" : "\(csvName) · \(csvRecipients.count) rows").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
            Text("Columns named name, email, phone, contact, address, city, state, pin, country and gstin fill the client details. Every other column becomes a field you can use in the text, e.g. {{field.amount_due}}.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            if !csvColumns.isEmpty {
                Text("Fields: " + csvColumns.map { "{{field.\($0)}}" }.joined(separator: "  ")).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
            }
            List(Array(csvRecipients.enumerated()), id: \.offset) { _, recipient in
                Text(recipient.party.name.isEmpty ? "(no name)" : recipient.party.name).font(.system(size: 12.5))
            }
            Toggle("Save new names as clients", isOn: $saveNewClients).font(.system(size: 12.5))
        }
    }

    private var options: some View {
        HStack(spacing: 18) {
            DatePicker("Date", selection: $issueDate, displayedComponents: .date).datePickerStyle(.field)
            Toggle("Issue them", isOn: $issue)
            Button(exportFolder.map { "PDFs → \($0.lastPathComponent)" } ?? "Also save PDFs to a folder…") {
                exportFolder = exportFolder == nil ? StorageLocation.chooseFolder(message: "Choose a folder for the PDFs", prompt: "Choose") : nil
            }
            .buttonStyle(.link)
        }
        .font(.system(size: 12.5))
    }

    private func resultView(_ result: BulkResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Created \(result.created.count) document\(result.created.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.success)
            if !result.exported.isEmpty {
                Text("\(result.exported.count) PDFs saved.").font(.system(size: 12.5))
            }
            if !result.failures.isEmpty {
                Text("Not created:").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                ForEach(Array(result.failures.enumerated()), id: \.offset) { _, failure in
                    Text("\(failure.name): \(failure.reason)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                if let folder = exportFolder, !result.exported.isEmpty {
                    Button("Show PDFs") { app.revealInFinder(folder) }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Done") {
                    dismiss()
                    app.navigate(to: .documents)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func chooseCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose a CSV file with one row per recipient"
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = CSV.records(text)
        csvRecipients = parsed.rows.map(BulkRecipient.init(record:)).filter { !$0.party.isEmpty }
        csvColumns = parsed.headers.filter { !BulkRecipient.partyColumnKeys.contains($0) }
        csvName = url.lastPathComponent
    }

    private func run() {
        guard let store = app.store else { return }
        var options = BulkOptions()
        options.issueDate = CalendarDate(issueDate)
        options.issue = issue
        options.exportFolder = exportFolder
        options.saveNewClients = mode == .csv && saveNewClients
        let list = recipients
        running = true
        Task { @MainActor in
            do {
                result = try store.bulkGenerate(from: source.id, recipients: list, options: options) { done, total in
                    Task { @MainActor in progress = total == 0 ? 1 : Double(done) / Double(total) }
                }
            } catch {
                app.show(error, title: "Bulk generation failed")
            }
            running = false
            app.refresh()
        }
    }
}

// MARK: - AI drafting

struct AIDraftSheet: View {
    @ObservedObject var model: DocumentEditorModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AIAssistant.shared
    @State private var request = ""
    @State private var output = ""
    @State private var working = false
    @State private var error: String?

    private let suggestions = [
        "An introduction paragraph thanking the client for the opportunity",
        "A scope of work with 5 deliverables for a website redesign",
        "Payment terms: 50% advance, 50% on delivery",
        "A polite reminder that the invoice is 15 days overdue",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(Color(hex: 0x7C3AED))
                Text("Draft with AI").font(.system(size: 19, weight: .bold))
                Spacer()
                Text("On-device · private").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            LabeledField(label: "What should it write?") {
                TextEditor(text: $request)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 70)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            }
            HStack {
                ForEach(suggestions.prefix(2), id: \.self) { suggestion in
                    Button(suggestion) { request = suggestion }.buttonStyle(.link).font(.system(size: 11.5)).lineLimit(1)
                }
            }
            if working {
                HStack { ProgressView().controlSize(.small); Text("Writing…").foregroundStyle(Theme.secondary) }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warning)
            }
            if !output.isEmpty {
                LabeledField(label: "Draft (editable)") {
                    TextEditor(text: $output)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 200)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("AI text can be wrong. Review it before issuing. It is not legal or tax advice.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button(output.isEmpty ? "Write Draft" : "Try Again") { generate() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                Button("Insert") {
                    model.richText.insert(RichTextBuilder.build(output, theme: model.theme), onNewParagraph: true)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(output.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private func generate() {
        working = true
        error = nil
        Task {
            do {
                output = try await ai.draft(request: request, document: model.document)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

/// Toolbar menu for AI actions on the rich-text body.
struct AIMenu: View {
    @ObservedObject var model: DocumentEditorModel
    @Binding var showDraft: Bool
    @ObservedObject private var ai = AIAssistant.shared
    @State private var working = false

    var body: some View {
        let status = ai.availability
        Menu {
            if !status.available {
                Text(status.reason)
            }
            Button("Draft New Text…") { showDraft = true }
            Divider()
            ForEach(AIAssistant.Rewrite.allCases) { style in
                Button(style.rawValue) { rewrite(style) }
            }
            Divider()
            Button("Insert Summary of Document") { summarize() }
        } label: {
            if working {
                ProgressView().controlSize(.small)
            } else {
                Label("AI", systemImage: "sparkles")
            }
        }
        .fixedSize()
        .disabled(!status.available || working)
        .help(status.available ? "Write and rewrite with Apple Intelligence, on this Mac" : status.reason)
    }

    private func rewrite(_ style: AIAssistant.Rewrite) {
        let selected = model.richText.selectedText
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.app.alert = AppAlert(title: "Select some text first", message: "Highlight the text you want rewritten, then choose \(style.rawValue).")
            return
        }
        working = true
        Task {
            do {
                let result = try await ai.rewrite(selected, style)
                model.richText.replaceSelection(with: RichTextBuilder.build(result, theme: model.theme))
            } catch {
                model.app.show(error, title: "AI couldn’t rewrite that")
            }
            working = false
        }
    }

    private func summarize() {
        let text = model.document.body.plainText
        guard !text.isEmpty else { return }
        working = true
        Task {
            do {
                let summary = try await ai.summarize(text)
                model.richText.insert(RichTextBuilder.build("## Summary\n" + summary, theme: model.theme), onNewParagraph: true)
            } catch {
                model.app.show(error, title: "AI couldn’t summarise")
            }
            working = false
        }
    }
}
