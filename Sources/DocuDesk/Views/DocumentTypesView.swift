import DocuDeskCore
import SwiftUI

/// Settings tab for user-defined document types and their fields.
struct DocumentTypesSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var types: [CustomDocumentType] = []
    @State private var editing: CustomDocumentType?
    @State private var showArchived = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your document types").font(.system(size: 14, weight: .semibold))
                        Text("Create types such as Work Order, Site Visit Report or Warranty Card with their own numbering, labels and fields.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Toggle("Show archived", isOn: $showArchived).toggleStyle(.checkbox).font(.system(size: 12))
                    Button { editing = CustomDocumentType(name: "") } label: { Label("New Type", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                if types.isEmpty {
                    Text("No custom types yet.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                }
                ForEach(types) { type in
                    HStack(spacing: 12) {
                        KindBadge(kind: .custom, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.name + (type.archived ? " (archived)" : "")).font(.system(size: 13.5, weight: .semibold))
                            Text("\(type.prefix) · \(type.layout.displayName) · \(type.fields.count) field\(type.fields.count == 1 ? "" : "s")")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if !type.archived {
                            Button("New \(type.name)") { model.createDocument(customType: type) }.buttonStyle(SecondaryButtonStyle())
                        }
                        Button("Edit…") { editing = type }.buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(10)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .task(id: "\(model.revision)-\(showArchived)") {
            types = (try? model.store?.customTypes(includeArchived: showArchived)) ?? []
        }
        .sheet(item: $editing) { type in
            CustomTypeEditor(type: type)
        }
    }
}

private struct CustomTypeEditor: View {
    @State var type: CustomDocumentType
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmDelete = false

    private var isNew: Bool { !model.customTypes.contains { $0.id == type.id } && (try? model.store?.customType(id: type.id)) == nil }
    private let selectableStatuses: [DocumentStatus] = [.issued, .sent, .accepted, .declined, .confirmed, .delivered, .signed, .cancelled]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(isNew ? "New Document Type" : "Edit \(type.name)").font(.system(size: 19, weight: .bold))
                    HStack(spacing: 12) {
                        LabeledField(label: "Name *") {
                            TextField("e.g. Work Order", text: $type.name).fieldStyle()
                                .onChange(of: type.name) { old, new in
                                    if type.printedTitle.isEmpty || type.printedTitle == old { type.printedTitle = new }
                                    if type.pluralName.isEmpty || type.pluralName == old + "s" { type.pluralName = new + "s" }
                                    if type.numberLabel.isEmpty || type.numberLabel == "\(old) No." { type.numberLabel = "\(new) No." }
                                }
                        }
                        LabeledField(label: "Plural (folder name)") { TextField("Work Orders", text: $type.pluralName).fieldStyle() }
                        LabeledField(label: "Number prefix") { TextField("WO", text: $type.prefix).fieldStyle().frame(width: 90) }
                    }
                    LabeledField(label: "Layout") {
                        Picker("", selection: $type.layout) {
                            ForEach(CustomLayout.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                    HStack(spacing: 12) {
                        LabeledField(label: "Printed title") { TextField("Work Order", text: $type.printedTitle).fieldStyle() }
                        LabeledField(label: "Recipient label") { TextField("Bill To", text: $type.partyLabel).fieldStyle() }
                        LabeledField(label: "Number label") { TextField("No.", text: $type.numberLabel).fieldStyle() }
                    }
                    HStack(spacing: 12) {
                        Toggle("Second date", isOn: Binding(get: { type.dueDateLabel != nil }, set: { type.dueDateLabel = $0 ? "Due date" : nil }))
                            .toggleStyle(.checkbox)
                        if type.dueDateLabel != nil {
                            TextField("Label", text: Binding(get: { type.dueDateLabel ?? "" }, set: { type.dueDateLabel = $0 })).fieldStyle().frame(width: 160)
                            Stepper("\(type.dueDays) days after the date", value: $type.dueDays, in: 0...365)
                        }
                        Spacer()
                    }
                    .font(.system(size: 12.5))
                    Toggle("Show prices, tax and totals", isOn: $type.showsPricing)
                        .disabled(type.layout == .text)
                        .font(.system(size: 12.5))
                    LabeledField(label: "Statuses after draft") {
                        HStack(spacing: 10) {
                            ForEach(selectableStatuses) { status in
                                Toggle(status.displayName, isOn: Binding(
                                    get: { type.statuses.contains(status) },
                                    set: { on in
                                        if on { type.statuses.append(status) } else { type.statuses.removeAll { $0 == status } }
                                        type.statuses = [.draft] + selectableStatuses.filter { type.statuses.contains($0) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        .font(.system(size: 12))
                    }
                    if type.layout != .items {
                        NoteEditor(label: "Starting text (markup: # heading, - bullet, {{field.key}})", text: $type.starterText, height: 90)
                    }
                    fieldsEditor
                    if let error {
                        Label(error, systemImage: "exclamationmark.octagon.fill").font(.system(size: 12.5)).foregroundStyle(Theme.danger)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                if !isNew {
                    Button("Delete…", role: .destructive) { confirmDelete = true }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save Type") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(type.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 820, height: 760)
        .confirmationDialog("Delete \(type.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                try? model.store?.deleteCustomType(id: type.id)
                model.refresh()
                dismiss()
            }
        } message: {
            Text("If documents already use this type, it’s archived instead so they keep working.")
        }
    }

    private var fieldsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fields").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { type.fields.append(CustomFieldDefinition(id: "", label: "")) } label: { Label("Add Field", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if type.fields.isEmpty {
                Text("Fields appear in the editor and, depending on placement, beside the number or in a Details section on the PDF.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach($type.fields) { $field in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Label", text: $field.label).fieldStyle()
                        Picker("", selection: $field.type) {
                            ForEach(CustomFieldType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        Picker("", selection: $field.placement) {
                            ForEach(CustomFieldPlacement.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        Toggle("Required", isOn: $field.required).toggleStyle(.checkbox).font(.system(size: 12))
                        Button { type.fields.removeAll { $0.id == field.id && $0.label == field.label } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    HStack(spacing: 8) {
                        if field.type == .choice {
                            TextField("Choices, separated by commas", text: Binding(
                                get: { field.choices.joined(separator: ", ") },
                                set: { field.choices = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                            )).fieldStyle()
                        }
                        TextField("Default value (optional)", text: $field.defaultValue).fieldStyle()
                        Text(field.id.isEmpty ? "{{field.\(CustomFieldDefinition.key(for: field.label))}}" : "{{field.\(field.id)}}")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func save() {
        guard let store = model.store else { return }
        type.fields.removeAll { $0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            try store.saveCustomType(type)
            model.refresh()
            model.flash("Saved \(type.name)")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
