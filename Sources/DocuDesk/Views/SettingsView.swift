import AppKit
import DocuDeskCore
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: String, CaseIterable, Identifiable {
    case companies = "Companies"
    case company = "Company Details"
    case documents = "Document Defaults"
    case types = "Document Types"
    case numbering = "Numbering"
    case appearance = "Appearance"

    var id: String { rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @State private var tab: SettingsTab = .company
    @State private var draft: CompanyProfile?
    @State private var addingProfile = false
    @State private var newProfileName = ""
    @State private var customTemplates: [CustomTemplate] = []

    private var hasChanges: Bool { draft != nil && draft != model.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Settings", subtitle: "Company profile, defaults and numbering. Changes apply to new documents only.") {
                if hasChanges {
                    Button("Discard") { draft = model.profile }.buttonStyle(SecondaryButtonStyle())
                }
                Button("Save Changes") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!hasChanges)
            }
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { item in
                    Button(item.rawValue) { tab = item }.buttonStyle(ChipButtonStyle(selected: tab == item))
                }
            }
            ScrollView {
                if draft != nil {
                    VStack(spacing: 16) {
                        switch tab {
                        case .companies: companiesTab
                        case .company: companyTab
                        case .documents: documentsTab
                        case .types: DocumentTypesSettings()
                        case .numbering: numberingTab
                        case .appearance: appearanceTab
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .onAppear {
            draft = model.profile
            customTemplates = (try? model.store?.customTemplates()) ?? []
        }
        .alert("Add Company Profile", isPresented: $addingProfile) {
            TextField("Business name", text: $newProfileName)
            Button("Add") { addProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each company has its own details, numbering, defaults and document folder.")
        }
        .onChange(of: model.profile) { _, profile in if !hasChanges { draft = profile } }
    }

    private var profile: Binding<CompanyProfile> {
        Binding(get: { draft ?? CompanyProfile(name: "") }, set: { draft = $0 })
    }

    private func save() {
        guard let store = model.store, let draft else { return }
        do {
            try store.saveProfile(draft)
            model.refresh()
            ThumbnailCache.shared.objectWillChange.send()
            model.flash("Settings saved")
        } catch {
            model.show(error)
        }
    }

    // MARK: Tabs

    private var companiesTab: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Company profiles").font(.system(size: 14, weight: .semibold))
                        Text("New documents use the active company. Switch any time from your avatar in the top bar.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button { newProfileName = ""; addingProfile = true } label: { Label("Add Company", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                ForEach(model.profiles) { profile in
                    let active = profile.id == model.profile?.id
                    let primary = profile.id == model.store?.primaryProfileID()
                    HStack(spacing: 12) {
                        Text(profile.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36, height: 36)
                            .background(Theme.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(profile.name).font(.system(size: 13.5, weight: .semibold))
                                if active {
                                    Text("Active")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.success)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Theme.success.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("\(profile.defaultCurrency) · Documents/\(primary ? "" : (profile.folderName.isEmpty ? profile.name : profile.folderName) + "/")…")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if !active {
                            Button("Make Active") { model.switchProfile(to: profile.id) }.buttonStyle(SecondaryButtonStyle())
                        }
                        if !primary {
                            Button("Delete") { deleteProfile(profile) }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(10)
                    .background(active ? Theme.accentSoft.opacity(0.5) : Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private func addProfile() {
        guard let store = model.store, !newProfileName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let profile = try store.createProfile(name: newProfileName, copyingDefaultsFrom: model.profile)
            model.switchProfile(to: profile.id)
            draft = model.profile
            tab = .company
        } catch {
            model.show(error)
        }
    }

    private func deleteProfile(_ profile: CompanyProfile) {
        do {
            try model.store?.deleteProfile(profile.id)
            model.refresh()
            draft = model.profile
        } catch {
            model.show(error, title: "Couldn’t delete \(profile.name)")
        }
    }

    private var companyTab: some View {
        Group {
            Card {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceMuted)
                            if let logo = model.store?.image(at: profile.wrappedValue.logoPath) {
                                Image(nsImage: logo).resizable().scaledToFit().padding(10)
                            } else {
                                Image(systemName: "photo").font(.system(size: 26)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .frame(width: 130, height: 130)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
                        Button("Choose Logo…") { chooseLogo() }.buttonStyle(SecondaryButtonStyle())
                        if profile.wrappedValue.logoPath != nil {
                            Button("Remove") { profile.wrappedValue.logoPath = nil }.buttonStyle(.link).font(.system(size: 12))
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            LabeledField(label: "Business name *") { TextField("Name", text: profile.name).fieldStyle() }
                            LabeledField(label: "Legal name (if different)") { TextField("Optional", text: profile.legalName).fieldStyle() }
                        }
                        HStack(spacing: 12) {
                            LabeledField(label: "Email") { TextField("Optional", text: profile.email).fieldStyle() }
                            LabeledField(label: "Phone") { TextField("Optional", text: profile.phone).fieldStyle() }
                            LabeledField(label: "Website") { TextField("Optional", text: profile.website).fieldStyle() }
                        }
                        HStack(spacing: 12) {
                            LabeledField(label: "Tax ID label") { TextField("GSTIN", text: profile.taxIDLabel).fieldStyle().frame(width: 120) }
                            LabeledField(label: "Tax ID") { TextField("Optional", text: profile.taxID).fieldStyle() }
                            LabeledField(label: "Authorised signatory") { TextField("Name", text: profile.signatoryName).fieldStyle() }
                        }
                    }
                }
            }
            Card { AddressFields(title: "Business address", address: profile.address) }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    NoteEditor(label: "Bank / payment details (printed on invoices)", text: profile.bankDetails, height: 80)
                    LabeledField(label: "UPI ID (for payment QR codes on invoices)") {
                        TextField("e.g. business@okhdfcbank", text: profile.upiID).fieldStyle().frame(maxWidth: 320)
                    }
                    Text("Turn on “UPI payment QR” in a custom template to print a scan-to-pay code for the balance due.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var documentsTab: some View {
        Group {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Money & tax").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 12) {
                        LabeledField(label: "Currency") {
                            Picker("", selection: profile.defaultCurrency) {
                                ForEach(CurrencyInfo.supported) { Text("\($0.code) · \($0.name)").tag($0.code) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Tax") {
                            Picker("", selection: profile.defaultTaxSplit) {
                                ForEach(TaxSplit.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Default rate %") { DecimalField(placeholder: "18", value: profile.defaultTaxRate).fieldStyle().frame(width: 90) }
                    }
                    LabeledField(label: "Pricing") {
                        Picker("", selection: profile.defaultTaxMode) {
                            ForEach(TaxMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Layout & dates").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 12) {
                        LabeledField(label: "Default template") {
                            Picker("", selection: Binding(
                                get: { profile.wrappedValue.defaultTemplateID ?? "style." + profile.wrappedValue.defaultTemplateStyle.rawValue },
                                set: { value in
                                    if value.hasPrefix("style."), let style = TemplateStyle(rawValue: String(value.dropFirst(6))) {
                                        profile.wrappedValue.defaultTemplateStyle = style
                                        profile.wrappedValue.defaultTemplateID = nil
                                    } else {
                                        profile.wrappedValue.defaultTemplateID = value
                                    }
                                })) {
                                ForEach(TemplateStyle.allCases) { Text($0.displayName).tag("style." + $0.rawValue) }
                                if !customTemplates.isEmpty {
                                    Divider()
                                    ForEach(customTemplates) { Text($0.name).tag($0.templateID) }
                                }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Paper size") {
                            Picker("", selection: profile.defaultPageSize) {
                                ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Payment terms (days)") {
                            TextField("15", value: profile.defaultPaymentTermsDays, format: .number).fieldStyle().frame(width: 90)
                        }
                        LabeledField(label: "Quote validity (days)") {
                            TextField("30", value: profile.defaultQuoteValidityDays, format: .number).fieldStyle().frame(width: 90)
                        }
                    }
                }
            }
            Card {
                VStack(spacing: 12) {
                    NoteEditor(label: "Default notes", text: profile.defaultNotes)
                    NoteEditor(label: "Default terms & conditions", text: profile.defaultTerms, height: 100)
                }
            }
        }
    }

    private var numberingTab: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Document numbers").font(.system(size: 14, weight: .semibold))
                Text("Numbers are unique per document type. DocuDesk skips any number that’s already used.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .padding(.bottom, 10)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("Type"); Text("Prefix"); Text("Year"); Text("Digits"); Text("Next"); Text("Yearly reset"); Text("Preview")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    ForEach(numberingSequences, id: \.key) { sequence in
                        let rule = ruleBinding(key: sequence.key, defaultPrefix: sequence.prefix)
                        GridRow {
                            HStack(spacing: 8) {
                                KindBadge(kind: sequence.kind, size: 24)
                                Text(sequence.name).font(.system(size: 13))
                            }
                            TextField("", text: rule.prefix).fieldStyle().frame(width: 80)
                            Toggle("", isOn: rule.includeYear).labelsHidden().toggleStyle(.checkbox)
                            Stepper("\(rule.wrappedValue.padding)", value: rule.padding, in: 1...8).font(.system(size: 12.5))
                            TextField("", value: rule.nextNumber, format: .number).fieldStyle().frame(width: 70)
                            Toggle("", isOn: rule.resetYearly).labelsHidden().toggleStyle(.checkbox).disabled(!rule.wrappedValue.includeYear)
                            Text(rule.wrappedValue.format(rule.wrappedValue.candidate(for: CalendarDate.today.year), year: CalendarDate.today.year))
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private var appearanceTab: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Appearance").font(.system(size: 14, weight: .semibold))
                Picker("", selection: $appearance) {
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 320)
                Text("Documents and PDFs always render on white paper, whatever the app appearance.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: Helpers

    private var numberingSequences: [(key: String, name: String, prefix: String, kind: DocumentKind)] {
        DocumentKind.builtIn.map { ($0.rawValue, $0.displayName, $0.defaultPrefix, $0) }
            + model.customTypes.map { ($0.key, $0.name, $0.prefix, DocumentKind.custom) }
    }

    private func ruleBinding(key: String, defaultPrefix: String) -> Binding<NumberingRule> {
        Binding(
            get: { profile.wrappedValue.numberingRule(forKey: key, defaultPrefix: defaultPrefix) },
            set: { profile.wrappedValue.numbering[key] = $0 }
        )
    }

    private func chooseLogo() {
        guard let store = model.store, let id = draft?.id else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .pdf]
        panel.message = "Choose a logo. It’s copied into the workspace’s Assets folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            draft?.logoPath = try store.importLogo(from: url, profileID: id)
        } catch {
            model.show(error, title: "Couldn’t use that logo")
        }
    }
}
