import AppKit
import DocuDeskCore
import SwiftUI
import UniformTypeIdentifiers

extension DocuDeskCore.RGBColor {
    var color: Color { Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)) }

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(resolved.redComponent), green: Double(resolved.greenComponent), blue: Double(resolved.blueComponent))
    }
}

private enum TemplatesTab: String, CaseIterable, Identifiable {
    case templates = "Templates"
    case clauses = "Clauses"
    var id: String { rawValue }
}

private enum TemplateSelection: Hashable {
    case builtIn(String)
    case custom(UUID)
}

struct TemplatesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: TemplatesTab = .templates

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(TemplatesTab.allCases) { item in
                    Button(item.rawValue) { tab = item }.buttonStyle(ChipButtonStyle(selected: tab == item))
                }
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            switch tab {
            case .templates: TemplateGallery()
            case .clauses: ClausesView()
            }
        }
    }
}

private struct TemplateGallery: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: DocumentCategory?
    @State private var style: TemplateStyle?
    @State private var favoritesOnly = false
    @State private var favorites: Set<String> = []
    @State private var customs: [CustomTemplate] = []
    @State private var selection: TemplateSelection = .builtIn("invoice.modern")
    @State private var previewKind: DocumentKind = .invoice
    @State private var previewData: Data?
    @State private var editing: CustomTemplate?
    @State private var confirmDelete: CustomTemplate?

    private var builtIns: [TemplateDefinition] {
        TemplateLibrary.all.filter { template in
            template.kind != .custom && (category == nil || template.kind.category == category)
                && (style == nil || template.style == style)
                && (!favoritesOnly || favorites.contains(template.id))
        }
    }

    private var selectedDefinition: TemplateDefinition {
        switch selection {
        case let .builtIn(id):
            return TemplateLibrary.template(id: id) ?? TemplateLibrary.defaultTemplate(for: .invoice, style: .modern)
        case let .custom(id):
            return customs.first { $0.id == id }?.definition(for: previewKind) ?? TemplateLibrary.defaultTemplate(for: previewKind, style: .modern)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Templates", subtitle: "\(TemplateLibrary.all.filter { $0.kind != .custom }.count) built-in templates across \(DocumentKind.builtIn.count) document types, plus your own") {
                    Button("Import…") { importTemplate() }.buttonStyle(SecondaryButtonStyle())
                    Button { newTemplate(from: .modern) } label: { Label("New Template", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        myTemplates
                        filters
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)], spacing: 18) {
                            ForEach(builtIns) { template in
                                BuiltInTile(template: template, selected: selection == .builtIn(template.id), favorite: favorites.contains(template.id)) {
                                    selection = .builtIn(template.id)
                                } toggleFavorite: {
                                    toggleFavorite(template)
                                } customize: {
                                    newTemplate(from: template.style)
                                } use: {
                                    model.createDocument(template.kind, templateID: template.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)

            previewPanel
                .frame(width: 410)
        }
        .onAppear(perform: load)
        .task(id: "\(selectedDefinition.id)-\(previewKind.rawValue)-\(selectedDefinition.theme.hashValue)") { await renderPreview() }
        .sheet(item: $editing) { template in
            TemplateEditorSheet(template: template) { saved in
                save(saved)
            }
        }
        .confirmationDialog("Delete this template?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete Template", role: .destructive) { if let template = confirmDelete { delete(template) } }
        } message: {
            Text("Issued documents keep their look. Drafts using it switch to a built-in style.")
        }
    }

    @ViewBuilder
    private var myTemplates: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Templates").font(.system(size: 15, weight: .semibold))
            if customs.isEmpty {
                Text("Make a template with your own colours, fonts and layout. Click “Customize” on any built-in template, or New Template.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)], spacing: 18) {
                    ForEach(customs) { template in
                        CustomTile(template: template, selected: selection == .custom(template.id),
                                   isDefault: model.profile?.defaultTemplateID == template.templateID) {
                            selection = .custom(template.id)
                        } edit: {
                            editing = template
                        } export: {
                            export(template)
                        } delete: {
                            confirmDelete = template
                        }
                    }
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            Text("Built-in").font(.system(size: 15, weight: .semibold)).padding(.trailing, 8)
            Button("All") { category = nil }.buttonStyle(ChipButtonStyle(selected: category == nil))
            ForEach(DocumentCategory.allCases) { item in
                Button(item.displayName) { category = item }.buttonStyle(ChipButtonStyle(selected: category == item))
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            Picker("", selection: $style) {
                Text("All styles").tag(TemplateStyle?.none)
                ForEach(TemplateStyle.allCases) { Text($0.displayName).tag(Optional($0)) }
            }
            .labelsHidden()
            .frame(width: 130)
            Toggle(isOn: $favoritesOnly) { Label("Favorites", systemImage: "star.fill") }
                .toggleStyle(.button)
            Spacer()
        }
    }

    private var previewPanel: some View {
        let definition = selectedDefinition
        let isCustom: Bool = { if case .custom = selection { return true }; return false }()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                KindBadge(kind: isCustom ? previewKind : definition.kind, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name).font(.system(size: 15, weight: .semibold))
                    Text(definition.summary).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
            }
            if isCustom {
                Picker("", selection: $previewKind) {
                    ForEach([DocumentKind.invoice, .quotation, .proposal, .agreement, .letter]) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            PagePreview(data: previewData)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
            HStack {
                Button("Make Default") { makeDefault() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isDefault(definition))
                Spacer()
                Button("Use Template") {
                    model.createDocument(isCustom ? previewKind : definition.kind, templateID: definition.id)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(Theme.surfaceMuted)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    // MARK: Actions

    private func load() {
        favorites = model.store?.favoriteTemplateIDs ?? []
        customs = (try? model.store?.customTemplates()) ?? []
    }

    private func renderPreview() async {
        let definition = selectedDefinition
        let kind: DocumentKind
        if case .custom = selection { kind = previewKind } else { kind = definition.kind }
        let document = SampleData.document(kind: kind, template: definition, company: model.profile)
        let logo = model.store?.image(at: model.profile?.logoPath)
        let theme = definition.theme
        previewData = await Task.detached { DocumentRenderer.pdfData(for: document, logo: logo, theme: theme) }.value
    }

    private func toggleFavorite(_ template: TemplateDefinition) {
        if favorites.contains(template.id) { favorites.remove(template.id) } else { favorites.insert(template.id) }
        try? model.store?.setFavoriteTemplateIDs(favorites)
    }

    private func newTemplate(from style: TemplateStyle) {
        editing = CustomTemplate(name: "My \(style.displayName)", baseStyle: style)
    }

    private func save(_ template: CustomTemplate) {
        guard let store = model.store else { return }
        do {
            let saved = try store.saveCustomTemplate(template)
            customs = (try? store.customTemplates()) ?? []
            selection = .custom(saved.id)
            model.refresh()
            model.flash(saved.version > 1 ? "Saved as version \(saved.version); issued documents keep their version" : "Template saved")
        } catch {
            model.show(error)
        }
    }

    private func delete(_ template: CustomTemplate) {
        guard let store = model.store else { return }
        do {
            try store.deleteCustomTemplate(id: template.id)
            if var profile = model.profile, profile.defaultTemplateID == template.templateID {
                profile.defaultTemplateID = nil
                try store.saveProfile(profile)
            }
            customs = (try? store.customTemplates()) ?? []
            selection = .builtIn("invoice.modern")
            model.refresh()
        } catch {
            model.show(error)
        }
    }

    private func export(_ template: CustomTemplate) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: TemplateFile.fileExtension) ?? .json]
        panel.nameFieldStringValue = "\(template.name).\(TemplateFile.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.store?.exportTemplate(template, to: url)
            model.flash("Exported \(url.lastPathComponent)")
        } catch {
            model.show(error)
        }
    }

    private func importTemplate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: TemplateFile.fileExtension) ?? .json, .json]
        panel.message = "Choose a DocuDesk template file"
        guard panel.runModal() == .OK, let url = panel.url, let store = model.store else { return }
        do {
            let imported = try store.importTemplate(from: url)
            customs = (try? store.customTemplates()) ?? []
            selection = .custom(imported.id)
            model.flash("Imported \(imported.name)")
        } catch {
            model.show(error, title: "Import failed")
        }
    }

    private func isDefault(_ definition: TemplateDefinition) -> Bool {
        guard let profile = model.profile else { return false }
        if let id = profile.defaultTemplateID { return id == definition.id }
        return CustomTemplate.id(from: definition.id) == nil && profile.defaultTemplateStyle == definition.style
    }

    private func makeDefault() {
        guard let store = model.store, var profile = model.profile else { return }
        let definition = selectedDefinition
        if CustomTemplate.id(from: definition.id) != nil {
            profile.defaultTemplateID = definition.id
        } else {
            profile.defaultTemplateID = nil
            profile.defaultTemplateStyle = definition.style
        }
        do {
            try store.saveProfile(profile)
            model.refresh()
            model.flash("\(definition.name) is now the default for \(profile.name)")
        } catch {
            model.show(error)
        }
    }
}

// MARK: - Tiles

private struct BuiltInTile: View {
    let template: TemplateDefinition
    let selected: Bool
    let favorite: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void
    let customize: () -> Void
    let use: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                TemplateThumbnail(template: template)
                Button(action: toggleFavorite) {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(favorite ? Color(hex: 0xF59E0B) : Theme.secondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .padding(6)
                .opacity(favorite || hovering ? 1 : 0)
            }
            HStack(spacing: 8) {
                KindBadge(kind: template.kind, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.kind.displayName).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(template.style.displayName).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if hovering {
                    Menu {
                        Button("Use Template", action: use)
                        Button("Customize…", action: customize)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: use)
        .simultaneousGesture(TapGesture().onEnded(select))
    }
}

private struct CustomTile: View {
    let template: CustomTemplate
    let selected: Bool
    let isDefault: Bool
    let select: () -> Void
    let edit: () -> Void
    let export: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TemplateThumbnail(template: template.definition(for: .invoice))
            HStack(spacing: 8) {
                Circle().fill(template.theme.accent.color).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text("v\(template.version) · \(isDefault ? "Default" : template.baseStyle.displayName)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Menu {
                    Button("Edit…", action: edit)
                    Button("Export…", action: export)
                    Divider()
                    Button("Delete…", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .simultaneousGesture(TapGesture().onEnded(select))
    }
}

// MARK: - Template editor

/// Section-based template designer: colours, fonts, header layout, table style and options,
/// with a live preview across document types.
struct TemplateEditorSheet: View {
    @State var template: CustomTemplate
    let onSave: (CustomTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var previewKind: DocumentKind = .invoice
    @State private var previewData: Data?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Template Designer").font(.system(size: 18, weight: .bold))
                    LabeledField(label: "Name") { TextField("Template name", text: $template.name).fieldStyle() }
                    LabeledField(label: "Start from") {
                        Picker("", selection: Binding(get: { template.baseStyle }, set: { style in
                            template.baseStyle = style
                            let note = template.theme.footerNote
                            template.theme = TemplateLibrary.theme(for: style)
                            template.theme.footerNote = note
                        })) {
                            ForEach(TemplateStyle.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                    }
                    section("Colours") {
                        HStack(spacing: 16) {
                            colorWell("Accent", \.accent)
                            colorWell("Text", \.ink)
                            colorWell("Secondary", \.muted)
                            colorWell("Tint", \.tint)
                        }
                    }
                    section("Typography") {
                        Picker("", selection: Binding(
                            get: { FontPairing.matching(template.theme)?.name ?? "" },
                            set: { name in
                                guard let pairing = FontPairing.all.first(where: { $0.name == name }) else { return }
                                template.theme.headingFont = pairing.heading
                                template.theme.bodyFont = pairing.body
                                template.theme.bodyBoldFont = pairing.bold
                            })) {
                            if FontPairing.matching(template.theme) == nil { Text("Custom").tag("") }
                            ForEach(FontPairing.all) { Text($0.name).font(.custom($0.body, size: 13)).tag($0.name) }
                        }
                        .labelsHidden()
                        Toggle("Uppercase document title", isOn: $template.theme.uppercaseTitle)
                    }
                    section("Layout") {
                        LabeledField(label: "Header") {
                            Picker("", selection: $template.theme.header) {
                                ForEach(HeaderLayout.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Items table") {
                            Picker("", selection: $template.theme.table) {
                                ForEach(TableStyle.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    section("Sections") {
                        Toggle("Show amount in words", isOn: inverted(\.hideAmountInWords))
                        Toggle("Show HSN/SAC column", isOn: inverted(\.hideHSN))
                        Toggle("Show signature block", isOn: inverted(\.hideSignature))
                        LabeledField(label: "Footer note") {
                            TextField("e.g. Subject to Pune jurisdiction", text: $template.theme.footerNote).fieldStyle()
                        }
                    }
                    section("Spacing & logo") {
                        LabeledField(label: "Density") {
                            Picker("", selection: $template.theme.density) {
                                ForEach(LayoutDensity.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        LabeledField(label: "Logo size") {
                            Picker("", selection: $template.theme.logoSize) {
                                ForEach(LogoSize.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    section("Items table") {
                        LabeledField(label: "Item column heading") {
                            TextField("Item & Description", text: $template.theme.itemColumnTitle).fieldStyle()
                        }
                        Toggle("Show row numbers", isOn: inverted(\.hideItemNumbers))
                        Toggle("Show tax % column", isOn: inverted(\.hideTaxColumn))
                    }
                    section("Section order") {
                        ForEach(Array(template.theme.orderedSections.enumerated()), id: \.element) { index, item in
                            HStack {
                                Text("\(index + 1). \(item.displayName)")
                                Spacer()
                                Button { moveSection(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(.borderless).disabled(index == 0)
                                Button { moveSection(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(.borderless).disabled(index == NoteSection.allCases.count - 1)
                            }
                        }
                    }
                    section("Extras") {
                        LabeledField(label: "Watermark") {
                            TextField("e.g. COPY, DUPLICATE, ORIGINAL", text: $template.theme.watermark).fieldStyle()
                        }
                        Toggle("UPI payment QR on unpaid invoices", isOn: $template.theme.showPaymentQR)
                        if template.theme.showPaymentQR, (model.profile?.upiID ?? "").isEmpty {
                            Text("Add your UPI ID in Settings → Company Details for the QR code to appear.")
                                .font(.system(size: 11)).foregroundStyle(Theme.warning)
                        }
                    }
                    Text("Saving a change creates a new version. Issued documents keep the version they were issued with.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 12.5))
                .padding(22)
            }
            .frame(width: 380)

            VStack(spacing: 12) {
                Picker("", selection: $previewKind) {
                    ForEach([DocumentKind.invoice, .quotation, .receipt, .proposal, .agreement]) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                PagePreview(data: previewData)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("Save Template") {
                        onSave(template)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .background(Theme.surfaceMuted)
        }
        .frame(width: 1040, height: 760)
        .task(id: "\(template.theme.hashValue)-\(previewKind.rawValue)") {
            try? await Task.sleep(for: .milliseconds(150))
            let document = SampleData.document(kind: previewKind, template: template.definition(for: previewKind), company: model.profile)
            let logo = model.store?.image(at: model.profile?.logoPath)
            let theme = template.theme
            previewData = await Task.detached { DocumentRenderer.pdfData(for: document, logo: logo, theme: theme) }.value
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.tertiary)
            content()
        }
    }

    private func colorWell(_ label: String, _ keyPath: WritableKeyPath<TemplateTheme, DocuDeskCore.RGBColor>) -> some View {
        VStack(spacing: 4) {
            ColorPicker("", selection: Binding(get: { template.theme[keyPath: keyPath].color }, set: { template.theme[keyPath: keyPath] = DocuDeskCore.RGBColor($0) }),
                        supportsOpacity: false)
                .labelsHidden()
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
        }
    }

    private func moveSection(_ index: Int, by offset: Int) {
        var order = template.theme.orderedSections
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        template.theme.sectionOrder = order.map(\.rawValue)
    }

    private func inverted(_ keyPath: WritableKeyPath<TemplateTheme, Bool>) -> Binding<Bool> {
        Binding(get: { !template.theme[keyPath: keyPath] }, set: { template.theme[keyPath: keyPath] = !$0 })
    }
}
