import DocuDeskCore
import SwiftUI

extension MoneyFormatter {
    /// `₹2,48,500` when whole, `₹1,234.50` otherwise.
    static func compact(_ amount: Decimal, currency: String) -> String {
        let text = format(amount, currency: currency)
        return amount == amount.rounded(0) && text.hasSuffix(".00") ? String(text.dropLast(3)) : text
    }
}

private enum CreateTab: String, CaseIterable, Identifiable {
    case popular = "Popular"
    case sales = "Sales"
    case purchase = "Purchase"
    case business = "Business"
    case finance = "Finance"

    var id: String { rawValue }

    var kinds: [DocumentKind] {
        switch self {
        case .popular: DocumentKind.popular
        case .sales: DocumentKind.builtIn.filter { $0.category == .sales }
        case .purchase: DocumentKind.builtIn.filter { $0.category == .purchase }
        case .business: DocumentKind.builtIn.filter { $0.category == .business }
        case .finance: DocumentKind.builtIn.filter { $0.category == .finance }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var preview = DocumentPreviewLoader()
    @State private var stats = DashboardStats()
    @State private var invoiceTotal: CurrencyAmount?
    @State private var quotationTotal: CurrencyAmount?
    @State private var invoicesThisMonth = 0
    @State private var quotationsThisMonth = 0
    @State private var documentsThisMonth = 0
    @State private var clientCount = 0
    @State private var clientsThisMonth = 0
    @State private var tab: CreateTab = .popular
    @State private var selectedID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting
                    if model.backupIsStale, stats.total > 0 { backupBanner }
                    statCards
                    createCard
                    recentCard
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
            }
            DocumentPreviewPanel(
                loader: preview,
                documents: stats.recent,
                selectedID: $selectedID
            )
            .frame(width: 390)
        }
        .task(id: model.revision) { reload() }
        .onChange(of: selectedID) { _, id in preview.load(id, store: model.store) }
    }

    private var currency: String { model.profile?.defaultCurrency ?? "INR" }

    private func reload() {
        guard let store = model.store else { return }
        let monthStart = CalendarDate(year: CalendarDate.today.year, month: CalendarDate.today.month, day: 1)
        stats = (try? store.dashboardStats()) ?? DashboardStats()
        func preferred(_ amounts: [CurrencyAmount]) -> CurrencyAmount? {
            amounts.first { $0.currency == currency } ?? amounts.first
        }
        invoiceTotal = preferred((try? store.issuedTotals(kinds: [.invoice])) ?? [])
        quotationTotal = preferred((try? store.issuedTotals(kinds: [.quotation, .estimate])) ?? [])
        invoicesThisMonth = (try? store.documentCount(kinds: [.invoice], since: monthStart)) ?? 0
        quotationsThisMonth = (try? store.documentCount(kinds: [.quotation, .estimate], since: monthStart)) ?? 0
        documentsThisMonth = (try? store.documentCount(since: monthStart)) ?? 0
        let customers = (try? store.customers()) ?? []
        clientCount = customers.count
        clientsThisMonth = customers.filter { CalendarDate($0.createdAt) >= monthStart }.count
        if selectedID == nil || !stats.recent.contains(where: { $0.id == selectedID }) {
            selectedID = stats.recent.first?.id
        }
        preview.load(selectedID, store: store)
    }

    // MARK: Sections

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(greetingText)! 👋")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Create professional documents, manage your business, all in one place.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Here’s what’s happening today.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 8)
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good Morning"
        case 12..<17: "Good Afternoon"
        default: "Good Evening"
        }
    }

    private var backupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(model.lastBackup.map { "Your last backup was \($0.relativeDescription)." } ?? "You haven’t backed up your documents yet.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            Spacer()
            Button(model.backupInProgress ? "Backing up…" : "Back Up Now") { model.backUp(to: nil) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.backupInProgress)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warning.opacity(0.3)))
    }

    private var statCards: some View {
        HStack(spacing: 16) {
            StatCard(icon: "doc.text.fill", tint: Color(hex: 0x7C3AED), title: "Total Invoices",
                     value: MoneyFormatter.compact(invoiceTotal?.amount ?? 0, currency: invoiceTotal?.currency ?? currency),
                     footnote: "\(invoicesThisMonth) this month")
            StatCard(icon: "doc.plaintext.fill", tint: Color(hex: 0x16A34A), title: "Total Quotations",
                     value: MoneyFormatter.compact(quotationTotal?.amount ?? 0, currency: quotationTotal?.currency ?? currency),
                     footnote: "\(quotationsThisMonth) this month")
            StatCard(icon: "doc.on.doc.fill", tint: Color(hex: 0xEA580C), title: "Total Documents",
                     value: "\(stats.total)",
                     footnote: "\(documentsThisMonth) this month")
            StatCard(icon: "person.2.fill", tint: Color(hex: 0x2563EB), title: "Total Clients",
                     value: "\(clientCount)",
                     footnote: "\(clientsThisMonth) this month")
        }
    }

    private var createCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Create New Document") {
                    Button { model.navigate(to: .templates) } label: {
                        HStack(spacing: 6) { Text("Browse All Templates"); Image(systemName: "arrow.right") }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    ForEach(CreateTab.allCases) { item in
                        Button(item.rawValue) { tab = item }
                            .buttonStyle(ChipButtonStyle(selected: tab == item))
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), alignment: .leading, spacing: 12) {
                    ForEach(tab.kinds) { kind in
                        TemplateKindCard(kind: kind, style: model.profile?.defaultTemplateStyle ?? .modern) {
                            model.createDocument(kind)
                        }
                    }
                }
            }
        }
    }

    private var recentCard: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Recent Documents") {
                    Button { model.navigate(to: .documents) } label: {
                        HStack(spacing: 6) { Text("View All"); Image(systemName: "arrow.right") }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)

                if stats.recent.isEmpty {
                    EmptyStateView(icon: "tray", title: "No documents yet", message: "Create your first invoice or quotation from the templates above.")
                } else {
                    DocumentTable(documents: stats.recent, selectedID: $selectedID)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

// MARK: - Components

struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    Text(value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold))
                        Text(footnote)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct TemplateKindCard: View {
    let kind: DocumentKind
    let style: TemplateStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    KindBadge(kind: kind, size: 22)
                    Text(kind.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                TemplateThumbnail(template: TemplateLibrary.defaultTemplate(for: kind, style: style))
            }
            .padding(10)
            .background(hovering ? Theme.accentSoft.opacity(0.5) : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hovering ? Theme.accent : Theme.border, lineWidth: hovering ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New \(kind.displayName)")
    }
}

/// Styled document rows shared by the dashboard and the documents screen.
struct DocumentTable: View {
    let documents: [DocumentSummary]
    @Binding var selectedID: UUID?
    var showsHeader = true
    /// When set, rows show checkboxes for bulk actions.
    var checked: Binding<Set<UUID>>?

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(spacing: 12) {
                    if let checked {
                        Toggle("", isOn: Binding(
                            get: { !documents.isEmpty && documents.allSatisfy { checked.wrappedValue.contains($0.id) } },
                            set: { all in checked.wrappedValue = all ? Set(documents.map(\.id)) : [] }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                    }
                    Text("Name").frame(width: 140, alignment: .leading)
                    Text("Type").frame(width: 104, alignment: .leading)
                    Text("Client").frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                    Text("Date").frame(width: 88, alignment: .leading)
                    Text("Amount").frame(width: 92, alignment: .trailing)
                    Text("Status").frame(width: 100, alignment: .leading)
                    Color.clear.frame(width: 28)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ForEach(documents) { document in
                DocumentRow(document: document, selected: selectedID == document.id, checked: checked) {
                    selectedID = document.id
                }
                if document.id != documents.last?.id {
                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1).padding(.horizontal, 12)
                }
            }
        }
    }
}

struct DocumentRow: View {
    let document: DocumentSummary
    let selected: Bool
    var checked: Binding<Set<UUID>>?
    let onSelect: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let checked {
                Toggle("", isOn: Binding(
                    get: { checked.wrappedValue.contains(document.id) },
                    set: { on in if on { checked.wrappedValue.insert(document.id) } else { checked.wrappedValue.remove(document.id) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 10) {
                KindBadge(kind: document.kind, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if document.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color(hex: 0xF59E0B))
                        }
                        Text(document.number)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if !document.tags.isEmpty || document.archived {
                        Text(((document.archived ? ["Archived"] : []) + document.tags).joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 140, alignment: .leading)
            .help(document.title)
            Text(document.typeName).lineLimit(1).minimumScaleFactor(0.85).frame(width: 104, alignment: .leading)
            Text(document.customerName.isEmpty ? "—" : document.customerName).lineLimit(1).frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
            Text(document.issueDate.display).frame(width: 88, alignment: .leading)
            Text(document.kind.showsPricing || (document.kind == .custom && document.total > 0) ? MoneyFormatter.compact(document.total, currency: document.currency) : "—")
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)
            StatusPill(status: document.effectiveStatus).frame(width: 100, alignment: .leading)
            Menu {
                Button("Open") { model.openDocument(document.id) }
                Button("Duplicate") { duplicate() }
                if let folder = try? model.store?.documentFolder(for: document.id) {
                    Button("Show in Finder") { model.revealInFinder(folder) }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text.opacity(0.9))
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.accentSoft.opacity(0.7) : hovering ? Theme.surfaceMuted : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.openDocument(document.id) }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
    }

    private func duplicate() {
        guard let store = model.store else { return }
        do {
            let copy = try store.duplicate(document.id)
            model.refresh()
            model.openDocument(copy.id)
        } catch {
            model.show(error, title: "Couldn’t duplicate")
        }
    }
}

// MARK: - Preview panel

struct DocumentPreviewPanel: View {
    @ObservedObject var loader: DocumentPreviewLoader
    let documents: [DocumentSummary]
    @Binding var selectedID: UUID?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(index == nil || index == 0)
                templateMenu
                Spacer()
                Button { open() } label: { Image(systemName: "pencil") }
                    .buttonStyle(IconButtonStyle())
                    .help("Edit")
                    .disabled(loader.document == nil)
                Button { export() } label: { Image(systemName: "arrow.down.to.line") }
                    .buttonStyle(IconButtonStyle())
                    .help("Export PDF")
                    .disabled(loader.document == nil)
                Menu {
                    Button("Next Document") { step(1) }
                    Button("Show in Finder") { reveal() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
                .disabled(loader.document == nil)
            }

            ZStack {
                if let data = loader.data {
                    PagePreview(data: data)
                } else if documents.isEmpty {
                    VStack(spacing: 12) {
                        TemplateThumbnail(template: TemplateLibrary.defaultTemplate(for: .invoice, style: model.profile?.defaultTemplateStyle ?? .modern))
                            .padding(.horizontal, 30)
                        Text("Sample preview. Your documents will appear here.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
        }
        .padding(18)
        .background(Theme.surfaceMuted)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private var index: Int? { documents.firstIndex { $0.id == selectedID } }

    private var templateMenu: some View {
        let document = loader.document
        let current = document.map { TemplateLibrary.resolve(id: $0.templateID, kind: $0.kind).template }
        return Menu {
            if let document, document.status == .draft {
                ForEach(TemplateLibrary.templates(for: document.kind)) { template in
                    Button(template.name) { apply(template) }
                }
            } else {
                Text("Issued documents keep their template")
            }
        } label: {
            Text(current?.name ?? "Preview").font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(document == nil)
    }

    private func step(_ delta: Int) {
        guard let index else { return }
        let next = index + delta
        if documents.indices.contains(next) { selectedID = documents[next].id }
    }

    private func open() {
        if let id = loader.document?.id { model.openDocument(id) }
    }

    private func apply(_ template: TemplateDefinition) {
        guard let store = model.store, var document = loader.document else { return }
        document.templateID = template.id
        document.templateVersion = template.version
        do {
            try store.save(document)
            loader.load(document.id, store: store)
        } catch {
            model.show(error)
        }
    }

    private func export() {
        guard let store = model.store, let document = loader.document else { return }
        do {
            let result = try store.exportPDF(document)
            model.refresh()
            model.revealInFinder(result.url)
        } catch {
            model.show(error, title: "Export failed")
        }
    }

    private func reveal() {
        guard let id = loader.document?.id, let folder = try? model.store?.documentFolder(for: id) else { return }
        model.revealInFinder(folder)
    }
}
