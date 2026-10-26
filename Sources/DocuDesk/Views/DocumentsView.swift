import AppKit
import DocuDeskCore
import SwiftUI
import UniformTypeIdentifiers

/// Standard page heading used by every main screen.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct DocumentsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var preview = DocumentPreviewLoader()
    @State private var results: [DocumentSummary] = []
    /// `kind.<raw>` for built-in kinds or `custom.<uuid>` for custom types.
    @State private var typeFilter: String?
    @State private var bulkSource: DocumentRecord?
    @State private var status: DocumentStatus?
    @State private var tag: String?
    @State private var profileID: UUID?
    @State private var archive: DocumentQuery.ArchiveFilter = .active
    @State private var pinnedOnly = false
    @State private var useDateRange = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var minAmount: Decimal = 0
    @State private var maxAmount: Decimal = 0
    @State private var selectedID: UUID?
    @State private var selecting = false
    @State private var checked: Set<UUID> = []
    @State private var allTags: [String] = []
    @State private var savedFilters: [SavedFilter] = []
    @State private var showRecent = false
    @State private var naming = false
    @State private var filterName = ""
    @State private var bulkTag = ""
    @State private var showBulkTag = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: showRecent ? "Recently Opened" : "Documents", subtitle: subtitle) {
                    savedFiltersMenu
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        checked = []
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Menu {
                        Button("Excel Workbook (.xlsx)…") { exportXLSX(results) }
                        Button("CSV…") { exportCSV(results) }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .fixedSize()
                    .disabled(results.isEmpty)
                }
                filters
                if selecting, !checked.isEmpty { bulkBar }
                Card(padding: 12) {
                    if results.isEmpty {
                        EmptyStateView(icon: "doc.text.magnifyingglass", title: "No matching documents",
                                       message: model.searchText.isEmpty ? "Try different filters, or create a new document." : "Nothing matches “\(model.searchText)”.")
                    } else {
                        ScrollView {
                            DocumentTable(documents: results, selectedID: $selectedID, checked: selecting ? $checked : nil)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)

            DocumentPreviewPanel(loader: preview, documents: results, selectedID: $selectedID)
                .frame(width: 390)
        }
        .task(id: queryKey) { search() }
        .onChange(of: selectedID) { _, id in preview.load(id, store: model.store) }
        .alert("Save Filter", isPresented: $naming) {
            TextField("Name", text: $filterName)
            Button("Save") { saveCurrentFilter() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current search and filters for one-click reuse.")
        }
        .sheet(item: $bulkSource) { source in BulkGenerateSheet(source: source) }
        .confirmationDialog("Delete the selected drafts?", isPresented: $confirmDelete) {
            Button("Move Drafts to Trash", role: .destructive) { deleteDrafts() }
        } message: {
            Text("Only drafts are deleted; issued documents in the selection are skipped. Drafts go to the macOS Trash.")
        }
    }

    private var subtitle: String {
        "\(results.count) document\(results.count == 1 ? "" : "s")" + (model.searchText.isEmpty ? "" : " matching “\(model.searchText)”")
            + (selecting ? " · \(checked.count) selected" : "")
    }

    private var currentQuery: DocumentQuery {
        var query = DocumentQuery()
        query.text = model.searchText
        if let typeFilter {
            if typeFilter.hasPrefix("kind."), let kind = DocumentKind(rawValue: String(typeFilter.dropFirst(5))) {
                query.kinds = [kind]
            } else if typeFilter.hasPrefix("custom."), let id = UUID(uuidString: String(typeFilter.dropFirst(7))) {
                query.customTypeID = id
            }
        }
        if let status { query.statuses = [status] }
        if let tag { query.tags = [tag] }
        query.profileID = profileID
        query.archive = archive
        query.pinnedOnly = pinnedOnly
        if useDateRange {
            query.from = CalendarDate(from)
            query.to = CalendarDate(to)
        }
        if minAmount > 0 { query.minAmount = minAmount }
        if maxAmount > 0 { query.maxAmount = maxAmount }
        return query
    }

    private var queryKey: String {
        [model.searchText, typeFilter ?? "", status?.rawValue ?? "", tag ?? "", profileID?.uuidString ?? "", archive.rawValue,
         "\(pinnedOnly)", "\(showRecent)", "\(useDateRange)", "\(from)", "\(to)", minAmount.plainString, maxAmount.plainString,
         "\(model.revision)"].joined(separator: "|")
    }

    private var hasFilters: Bool {
        typeFilter != nil || status != nil || tag != nil || profileID != nil || archive != .active || pinnedOnly || useDateRange
            || minAmount != 0 || maxAmount != 0 || !model.searchText.isEmpty || showRecent
    }

    // MARK: Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Type", selection: $typeFilter) {
                    Text("All types").tag(String?.none)
                    Divider()
                    ForEach(DocumentKind.builtIn) { Text($0.pluralName).tag(Optional("kind." + $0.rawValue)) }
                    if !model.customTypes.isEmpty {
                        Divider()
                        ForEach(model.customTypes) { Text($0.pluralName).tag(Optional("custom." + $0.id.uuidString)) }
                    }
                }
                .frame(width: 180)
                Picker("Status", selection: $status) {
                    Text("Any status").tag(DocumentStatus?.none)
                    Divider()
                    ForEach(DocumentStatus.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                .frame(width: 160)
                Picker("Tag", selection: $tag) {
                    Text("Any tag").tag(String?.none)
                    if !allTags.isEmpty { Divider() }
                    ForEach(allTags, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .frame(width: 140)
                if model.profiles.count > 1 {
                    Picker("Company", selection: $profileID) {
                        Text("All companies").tag(UUID?.none)
                        ForEach(model.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .frame(width: 200)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Picker("", selection: $archive) {
                    Text("Active").tag(DocumentQuery.ArchiveFilter.active)
                    Text("Archived").tag(DocumentQuery.ArchiveFilter.archived)
                    Text("All").tag(DocumentQuery.ArchiveFilter.all)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
                Toggle("Pinned", isOn: $pinnedOnly).toggleStyle(.checkbox)
                Toggle("Recently opened", isOn: $showRecent).toggleStyle(.checkbox)
                Toggle("Dates", isOn: $useDateRange).toggleStyle(.checkbox)
                if useDateRange {
                    DatePicker("", selection: $from, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                    Text("to").foregroundStyle(Theme.secondary)
                    DatePicker("", selection: $to, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                }
                HStack(spacing: 4) {
                    Text("Amount").foregroundStyle(Theme.secondary).fixedSize()
                    DecimalField(placeholder: "min", value: $minAmount).fieldStyle().frame(width: 76)
                    Text("–").foregroundStyle(Theme.secondary)
                    DecimalField(placeholder: "max", value: $maxAmount).fieldStyle().frame(width: 76)
                }
                Spacer()
                if hasFilters {
                    Button("Clear") { clearFilters() }.buttonStyle(.link)
                }
            }
        }
        .font(.system(size: 12.5))
    }

    private var savedFiltersMenu: some View {
        Menu {
            if savedFilters.isEmpty {
                Text("No saved filters yet")
            }
            ForEach(savedFilters) { filter in
                Button(filter.name) { apply(filter.query) }
            }
            Divider()
            Button("Save Current Filters…") {
                filterName = ""
                naming = true
            }
            .disabled(!hasFilters || showRecent)
            if !savedFilters.isEmpty {
                Menu("Delete") {
                    ForEach(savedFilters) { filter in
                        Button(filter.name, role: .destructive) { deleteFilter(filter) }
                    }
                }
            }
        } label: {
            Label("Saved Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
    }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(checked.count) selected").font(.system(size: 12.5, weight: .semibold))
            Spacer()
            Button("Export PDFs…") { exportPDFs() }
            Button("Export Records…") { exportRecords() }
            Button("Export Excel") { exportXLSX(results.filter { checked.contains($0.id) }) }
            if checked.count == 1, let id = checked.first {
                Button("Generate for Many…") { bulkSource = try? model.store?.loadDocument(id: id) }
            }
            Button("Tag…") { showBulkTag = true }
                .popover(isPresented: $showBulkTag) { bulkTagPopover }
            Button("Pin") { bulk { try $0.setPinned(true, for: Array(checked)) } }
            Button(archive == .archived ? "Unarchive" : "Archive") { bulk { try $0.setArchived(archive != .archived, for: Array(checked)) } }
            Button("Delete Drafts…", role: .destructive) { confirmDelete = true }
        }
        .buttonStyle(SecondaryButtonStyle())
        .padding(10)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var bulkTagPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Tag", text: $bulkTag).fieldStyle()
            HStack {
                Button("Add Tag") {
                    let value = bulkTag
                    bulk { try $0.addTag(value, to: Array(checked)) }
                    showBulkTag = false
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Remove Tag") {
                    let value = bulkTag
                    bulk { try $0.removeTag(value, from: Array(checked)) }
                    showBulkTag = false
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(bulkTag.trimmingCharacters(in: .whitespaces).isEmpty)
            if !allTags.isEmpty {
                Text(allTags.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: Actions

    private func search() {
        guard let store = model.store else { return }
        allTags = (try? store.allTags()) ?? []
        savedFilters = store.savedFilters()
        if showRecent {
            results = store.recentlyOpened()
        } else {
            do {
                results = try store.search(currentQuery)
            } catch {
                results = []
                model.show(error, title: "Search failed")
            }
        }
        checked = checked.intersection(results.map(\.id))
        if selectedID == nil || !results.contains(where: { $0.id == selectedID }) {
            selectedID = results.first?.id
        }
        preview.load(selectedID, store: store)
    }

    private func clearFilters() {
        typeFilter = nil
        status = nil
        tag = nil
        profileID = nil
        archive = .active
        pinnedOnly = false
        showRecent = false
        useDateRange = false
        minAmount = 0
        maxAmount = 0
        model.searchText = ""
    }

    private func apply(_ query: DocumentQuery) {
        clearFilters()
        model.searchText = query.text
        typeFilter = query.customTypeID.map { "custom." + $0.uuidString } ?? query.kinds.first.map { "kind." + $0.rawValue }
        status = query.statuses.first
        tag = query.tags.first
        profileID = query.profileID
        archive = query.archive
        pinnedOnly = query.pinnedOnly
        if let start = query.from, let end = query.to {
            useDateRange = true
            from = start.date
            to = end.date
        }
        minAmount = query.minAmount ?? 0
        maxAmount = query.maxAmount ?? 0
    }

    private func saveCurrentFilter() {
        guard let store = model.store, !filterName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var filters = store.savedFilters()
        filters.append(SavedFilter(name: filterName.trimmingCharacters(in: .whitespaces), query: currentQuery))
        do {
            try store.setSavedFilters(filters)
            savedFilters = filters
            model.flash("Saved filter “\(filterName)”")
        } catch {
            model.show(error)
        }
    }

    private func deleteFilter(_ filter: SavedFilter) {
        guard let store = model.store else { return }
        let filters = store.savedFilters().filter { $0.id != filter.id }
        try? store.setSavedFilters(filters)
        savedFilters = filters
    }

    private func bulk(_ action: (WorkspaceStore) throws -> Void) {
        guard let store = model.store else { return }
        do {
            try action(store)
            model.refresh()
        } catch {
            model.show(error, title: "Bulk action failed")
        }
    }

    private func exportPDFs() {
        guard let folder = StorageLocation.chooseFolder(message: "Choose a folder for the PDFs", prompt: "Export") else { return }
        bulk { store in
            let urls = try store.exportPDFs(Array(checked), to: folder)
            model.flash("Exported \(urls.count) PDF\(urls.count == 1 ? "" : "s")")
            model.revealInFinder(folder)
        }
    }

    private func exportRecords() {
        guard let folder = StorageLocation.chooseFolder(message: "Choose where to copy the selected records", prompt: "Export") else { return }
        bulk { store in
            let root = try store.exportRecords(Array(checked), to: folder)
            model.revealInFinder(root)
        }
    }

    private func deleteDrafts() {
        bulk { store in
            let skipped = try store.deleteDrafts(Array(checked))
            checked = []
            model.flash(skipped.isEmpty ? "Drafts moved to the Trash" : "Skipped issued: \(skipped.joined(separator: ", "))")
        }
    }

    private func exportXLSX(_ rows: [DocumentSummary]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = "DocuDesk Documents \(CalendarDate.today.iso).xlsx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.store?.exportListXLSX(rows, to: url)
            model.flash("Exported \(rows.count) rows to Excel")
        } catch {
            model.show(error, title: "Excel export failed")
        }
    }

    private func exportCSV(_ rows: [DocumentSummary]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "DocuDesk Documents \(CalendarDate.today.iso).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func field(_ value: String) -> String {
            value.contains(where: { ",\"\n".contains($0) }) ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
        }
        var lines = ["Number,Type,Client,Date,Due Date,Currency,Total,Balance,Status,Tags"]
        for document in rows {
            lines.append([
                document.number, document.typeName, document.customerName, document.issueDate.iso,
                document.dueDate?.iso ?? "", document.currency, document.total.plainString, document.balance.plainString,
                document.effectiveStatus.displayName, document.tags.joined(separator: "; "),
            ].map(field).joined(separator: ","))
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            model.flash("Exported \(rows.count) rows")
        } catch {
            model.show(error, title: "CSV export failed")
        }
    }
}
