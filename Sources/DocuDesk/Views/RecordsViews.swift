import AppKit
import DocuDeskCore
import SwiftUI

/// Reads a CSV file chosen by the user, or nil if cancelled.
@MainActor
func chooseCSVText(message: String) -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.commaSeparatedText, .plainText]
    panel.message = message
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
}

/// Two-pane list/editor layout shared by Clients and Products.
private struct RecordList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @Binding var selection: Item.ID?
    @Binding var filter: String
    let placeholder: String
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField(placeholder, text: $filter).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(12)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            row(item)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(selection == item.id ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture { selection = item.id }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}

private struct Avatar: View {
    let name: String
    var tint: Color = Theme.accent

    var body: some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.12), in: Circle())
    }
}

// MARK: - Clients

struct ClientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var customers: [Customer] = []
    @State private var showArchived = false
    @State private var filter = ""
    @State private var selection: UUID?
    @State private var draft: Customer?
    @State private var documents: [DocumentSummary] = []

    private var filtered: [Customer] {
        guard !filter.isEmpty else { return customers }
        return customers.filter { [$0.name, $0.email, $0.contactPerson, $0.taxID].joined(separator: " ").localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Clients", subtitle: "\(customers.count) client\(customers.count == 1 ? "" : "s") saved for reuse") {
                Toggle("Show archived", isOn: $showArchived).toggleStyle(.checkbox).font(.system(size: 12.5))
                Button("Import CSV…") { importCSV() }.buttonStyle(SecondaryButtonStyle())
                    .help("Columns: name, email, phone, contact, address, city, state, pin, country, gstin, currency, payment_terms, notes")
                Button { newClient() } label: { Label("New Client", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            HStack(alignment: .top, spacing: 18) {
                RecordList(items: filtered, selection: $selection, filter: $filter, placeholder: "Search clients") { customer in
                    HStack(spacing: 10) {
                        Avatar(name: customer.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customer.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(customer.email.isEmpty ? customer.billingAddress.city : customer.email)
                                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        if customer.archived {
                            Text("Archived").font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .frame(width: 320)

                if draft != nil {
                    ScrollView { editor }
                } else {
                    Card { EmptyStateView(icon: "person.2", title: "No client selected", message: "Choose a client, or add one to reuse their details on every document.") }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .task(id: "\(model.revision)-\(showArchived)") { load() }
        .onChange(of: selection) { _, id in select(id) }
    }

    private func load() {
        customers = (try? model.store?.customers(includeArchived: showArchived)) ?? []
        if selection == nil { selection = customers.first?.id }
        select(selection)
    }

    private func select(_ id: UUID?) {
        guard let id, let store = model.store else {
            documents = []
            return
        }
        if draft?.id != id { draft = customers.first { $0.id == id } ?? (try? store.customer(id: id)) }
        var query = DocumentQuery()
        query.customerID = id
        documents = (try? store.search(query)) ?? []
    }

    private func importCSV() {
        guard let text = chooseCSVText(message: "Choose a CSV of clients (first row = column names)"), let store = model.store else { return }
        do {
            let result = try store.importCustomers(csv: text)
            model.refresh()
            model.flash("Imported \(result.added) client\(result.added == 1 ? "" : "s")" + (result.skipped.isEmpty ? "" : " · \(result.skipped.count) already existed"))
        } catch {
            model.show(error, title: "Import failed")
        }
    }

    private func newClient() {
        let customer = Customer(name: "")
        draft = customer
        selection = nil
    }

    @ViewBuilder
    private var editor: some View {
        let binding = Binding(get: { draft ?? Customer(name: "") }, set: { draft = $0 })
        let isNew = !customers.contains { $0.id == binding.wrappedValue.id }
        VStack(spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(isNew ? "New Client" : "Client Details").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Picker("", selection: binding.isCompany) {
                            Text("Company").tag(true)
                            Text("Individual").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    HStack(spacing: 12) {
                        LabeledField(label: "Name *") { TextField("Client name", text: binding.name).fieldStyle() }
                        LabeledField(label: "Contact person") { TextField("Optional", text: binding.contactPerson).fieldStyle() }
                    }
                    HStack(spacing: 12) {
                        LabeledField(label: "Email") { TextField("Optional", text: binding.email).fieldStyle() }
                        LabeledField(label: "Phone") { TextField("Optional", text: binding.phone).fieldStyle() }
                    }
                    HStack(spacing: 12) {
                        LabeledField(label: "GSTIN / tax ID") { TextField("Optional", text: binding.taxID).fieldStyle() }
                        LabeledField(label: "Default currency") {
                            Picker("", selection: binding.defaultCurrency) {
                                Text("Company default").tag("")
                                ForEach(CurrencyInfo.supported) { Text($0.code).tag($0.code) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Payment terms (days)") {
                            TextField("Default", value: binding.paymentTermsDays, format: .number).fieldStyle()
                        }
                    }
                    AddressFields(title: "Billing address", address: binding.billingAddress)
                    Toggle("Shipping address is the same as billing", isOn: binding.shippingSameAsBilling).font(.system(size: 12.5))
                    if !binding.wrappedValue.shippingSameAsBilling {
                        AddressFields(title: "Shipping address", address: binding.shippingAddress)
                    }
                    NoteEditor(label: "Notes", text: binding.notes)
                    HStack {
                        if !isNew {
                            Button(binding.wrappedValue.archived ? "Unarchive" : "Archive") {
                                binding.wrappedValue.archived.toggle()
                                save()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button("Delete", role: .destructive) { delete() }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(!documents.isEmpty)
                                .help(documents.isEmpty ? "Delete this client" : "Clients with documents can be archived, not deleted")
                        }
                        Spacer()
                        if !isNew {
                            Menu("New Document") {
                                ForEach(DocumentKind.builtIn) { kind in
                                    Button(kind.displayName) { model.createDocument(kind, customer: binding.wrappedValue) }
                                }
                                if !model.customTypes.isEmpty {
                                    Divider()
                                    ForEach(model.customTypes) { type in
                                        Button(type.name) { model.createDocument(customType: type, customer: binding.wrappedValue) }
                                    }
                                }
                            }
                            .fixedSize()
                        }
                        Button(isNew ? "Add Client" : "Save Changes") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(binding.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Saved documents keep the client details they were issued with; editing here only affects new documents.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
            }
            if !documents.isEmpty {
                Card(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Documents (\(documents.count))").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 8).padding(.top, 4)
                        DocumentTable(documents: documents, selectedID: .constant(nil), showsHeader: false)
                    }
                }
            }
        }
    }

    private func save() {
        guard let store = model.store, var customer = draft else { return }
        customer.name = customer.name.trimmingCharacters(in: .whitespaces)
        do {
            try store.saveCustomer(customer)
            draft = customer
            selection = customer.id
            model.refresh()
            model.flash("Saved \(customer.name)")
        } catch {
            model.show(error)
        }
    }

    private func delete() {
        guard let store = model.store, let customer = draft else { return }
        do {
            if try store.deleteCustomer(id: customer.id) {
                draft = nil
                selection = nil
                model.refresh()
            } else {
                model.alert = AppAlert(title: "Client has documents", message: "Archive the client instead, so existing documents keep their link.")
            }
        } catch {
            model.show(error)
        }
    }
}

// MARK: - Products & Services

struct ProductsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var products: [ProductService] = []
    @State private var showArchived = false
    @State private var filter = ""
    @State private var selection: UUID?
    @State private var draft: ProductService?

    private var filtered: [ProductService] {
        guard !filter.isEmpty else { return products }
        return products.filter { [$0.name, $0.sku, $0.details, $0.hsnSac].joined(separator: " ").localizedCaseInsensitiveContains(filter) }
    }

    private var currency: String { model.profile?.defaultCurrency ?? "INR" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Products & Services", subtitle: "Your catalog of items, services and default prices") {
                Toggle("Show archived", isOn: $showArchived).toggleStyle(.checkbox).font(.system(size: 12.5))
                Button("Import CSV…") { importCSV() }.buttonStyle(SecondaryButtonStyle())
                    .help("Columns: name, description, sku, hsn, unit, price, tax, service")
                Button { newProduct() } label: { Label("New Item", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            HStack(alignment: .top, spacing: 18) {
                RecordList(items: filtered, selection: $selection, filter: $filter, placeholder: "Search catalog") { product in
                    HStack(spacing: 10) {
                        Image(systemName: product.isService ? "wrench.and.screwdriver.fill" : "shippingbox.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(product.isService ? Color(hex: 0x7C3AED) : Color(hex: 0xEA580C))
                            .frame(width: 34, height: 34)
                            .background((product.isService ? Color(hex: 0x7C3AED) : Color(hex: 0xEA580C)).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(product.sku.isEmpty ? (product.isService ? "Service" : "Product") : product.sku)
                                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(MoneyFormatter.compact(product.price, currency: product.currency.isEmpty ? currency : product.currency))
                            .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                    }
                }
                .frame(width: 360)

                if draft != nil {
                    ScrollView { editor }
                } else {
                    Card { EmptyStateView(icon: "cart", title: "No item selected", message: "Saved items can be added to any document in one click. One-off items don’t need to be saved here.") }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .task(id: "\(model.revision)-\(showArchived)") { load() }
        .onChange(of: selection) { _, id in
            if let id, draft?.id != id { draft = products.first { $0.id == id } }
        }
    }

    private func load() {
        products = (try? model.store?.products(includeArchived: showArchived)) ?? []
        if selection == nil { selection = products.first?.id }
        if let selection { draft = products.first { $0.id == selection } }
    }

    private func importCSV() {
        guard let text = chooseCSVText(message: "Choose a CSV of products and services (first row = column names)"), let store = model.store else { return }
        do {
            let result = try store.importProducts(csv: text)
            model.refresh()
            model.flash("Imported \(result.added) item\(result.added == 1 ? "" : "s")" + (result.skipped.isEmpty ? "" : " · \(result.skipped.count) already existed"))
        } catch {
            model.show(error, title: "Import failed")
        }
    }

    private func newProduct() {
        var product = ProductService(name: "")
        product.taxRate = model.profile?.defaultTaxRate ?? 0
        draft = product
        selection = nil
    }

    @ViewBuilder
    private var editor: some View {
        let binding = Binding(get: { draft ?? ProductService(name: "") }, set: { draft = $0 })
        let isNew = !products.contains { $0.id == binding.wrappedValue.id }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(isNew ? "New Item" : "Item Details").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Picker("", selection: binding.isService) {
                        Text("Product").tag(false)
                        Text("Service").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                LabeledField(label: "Name *") { TextField("e.g. Website maintenance", text: binding.name).fieldStyle() }
                NoteEditor(label: "Description", text: binding.details, height: 54)
                HStack(spacing: 12) {
                    LabeledField(label: "SKU / code") { TextField("Optional", text: binding.sku).fieldStyle() }
                    LabeledField(label: "HSN / SAC") { TextField("Optional", text: binding.hsnSac).fieldStyle() }
                    LabeledField(label: "Unit") { TextField("nos, hrs, kg…", text: binding.unit).fieldStyle() }
                }
                HStack(spacing: 12) {
                    LabeledField(label: "Default price") { DecimalField(placeholder: "0.00", value: binding.price).fieldStyle() }
                    LabeledField(label: "Currency") {
                        Picker("", selection: binding.currency) {
                            Text("Company default").tag("")
                            ForEach(CurrencyInfo.supported) { Text($0.code).tag($0.code) }
                        }
                        .labelsHidden()
                    }
                    LabeledField(label: "Tax rate %") { DecimalField(placeholder: "0", value: binding.taxRate).fieldStyle() }
                }
                HStack {
                    if !isNew {
                        Button(binding.wrappedValue.archived ? "Unarchive" : "Archive") {
                            binding.wrappedValue.archived.toggle()
                            save()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                    Button(isNew ? "Add Item" : "Save Changes") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(binding.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Documents copy the item’s details when it’s added, so later price changes never alter existing documents.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func save() {
        guard let store = model.store, var product = draft else { return }
        product.name = product.name.trimmingCharacters(in: .whitespaces)
        do {
            try store.saveProduct(product)
            draft = product
            selection = product.id
            model.refresh()
            model.flash("Saved \(product.name)")
        } catch {
            model.show(error)
        }
    }
}
