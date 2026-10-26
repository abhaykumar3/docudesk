import DocuDeskCore
import SwiftUI

/// Library of reusable clauses and snippets, insertable into terms and rich-text bodies.
struct ClausesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var clauses: [Clause] = []
    @State private var selection: UUID?
    @State private var draft: Clause?
    @State private var filter = ""

    private var filtered: [Clause] {
        guard !filter.isEmpty else { return clauses }
        return clauses.filter { "\($0.title) \($0.category) \($0.text)".localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Clauses", subtitle: "Reusable terms and paragraphs for invoices, agreements and letters") {
                Button { newClause() } label: { Label("New Clause", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            HStack(alignment: .top, spacing: 18) {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                            TextField("Search clauses", text: $filter).textFieldStyle(.plain)
                        }
                        .font(.system(size: 13))
                        .padding(12)
                        Rectangle().fill(Theme.border).frame(height: 1)
                        List(selection: $selection) {
                            ForEach(ClauseLibrary.categories + extraCategories, id: \.self) { category in
                                let items = filtered.filter { $0.category == category }
                                if !items.isEmpty {
                                    Section(category) {
                                        ForEach(items) { clause in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(clause.title).font(.system(size: 13, weight: .medium))
                                                Text(clause.text).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                            }
                                            .padding(.vertical, 3)
                                            .tag(clause.id)
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.sidebar)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(width: 340)

                if draft != nil {
                    editor
                } else {
                    Card { EmptyStateView(icon: "text.quote", title: "No clause selected", message: "Choose a clause to edit, or create a new one.") }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .onAppear(perform: load)
        .onChange(of: selection) { _, id in
            if let id { draft = clauses.first { $0.id == id } }
        }
    }

    private var extraCategories: [String] {
        Array(Set(clauses.map(\.category)).subtracting(ClauseLibrary.categories)).sorted()
    }

    private var editor: some View {
        let binding = Binding(get: { draft ?? Clause(title: "", category: "General", text: "") }, set: { draft = $0 })
        let isNew = !clauses.contains { $0.id == binding.wrappedValue.id }
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(isNew ? "New Clause" : "Edit Clause").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    LabeledField(label: "Title") { TextField("Clause title", text: binding.title).fieldStyle() }
                    LabeledField(label: "Category") {
                        Picker("", selection: binding.category) {
                            ForEach(ClauseLibrary.categories + extraCategories, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
                NoteEditor(label: "Text", text: binding.text, height: 220)
                Text("Use **bold**, - bullets, 1. numbered items and fields like {{client.name}}. Each line becomes a paragraph.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                HStack {
                    if !isNew {
                        Button("Delete", role: .destructive) { delete() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                    Button(isNew ? "Add Clause" : "Save Changes") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(binding.wrappedValue.title.trimmingCharacters(in: .whitespaces).isEmpty || binding.wrappedValue.text.isEmpty)
                }
            }
        }
    }

    private func load() {
        clauses = (try? model.store?.clauses()) ?? []
        if selection == nil { selection = clauses.first?.id }
    }

    private func newClause() {
        selection = nil
        draft = Clause(title: "", category: "General", text: "")
    }

    private func save() {
        guard let store = model.store, let clause = draft else { return }
        do {
            try store.saveClause(clause)
            clauses = try store.clauses()
            selection = clause.id
            model.flash("Clause saved")
        } catch {
            model.show(error)
        }
    }

    private func delete() {
        guard let store = model.store, let clause = draft else { return }
        do {
            try store.deleteClause(id: clause.id)
            clauses = try store.clauses()
            draft = nil
            selection = clauses.first?.id
        } catch {
            model.show(error)
        }
    }
}
