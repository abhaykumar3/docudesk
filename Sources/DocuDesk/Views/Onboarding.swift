import AppKit
import Darwin
import DocuDeskCore
import SwiftUI
import UniformTypeIdentifiers

/// Modal password prompt with a secure field.
@MainActor
func askForPassword(message: String) -> String? {
    let alert = NSAlert()
    alert.messageText = "Password Required"
    alert.informativeText = message
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
    return field.stringValue
}

enum StorageLocation {
    /// True when the folder (or its nearest existing parent) is managed by iCloud Drive, including
    /// "Desktop & Documents" sync. SQLite databases there can be corrupted by sync.
    static func isCloudSynced(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current.deleteLastPathComponent()
        }
        while current.path != "/" {
            if hasCloudAttribute(current) { return true }
            if (try? current.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { return true }
            current.deleteLastPathComponent()
        }
        return current.path.contains("/Library/Mobile Documents/")
    }

    private static func hasCloudAttribute(_ url: URL) -> Bool {
        let name = "com.apple.file-provider-domain-id"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: size)
        getxattr(url.path, name, &buffer, size, 0, 0)
        return String(decoding: buffer, as: UTF8.self).contains("CloudDocs")
    }

    /// `~/Documents/DocuDesk`, unless Documents is synced by iCloud, in which case `~/DocuDesk`.
    static var recommendedDefault: URL {
        let documents = Workspace.defaultLocation
        if isCloudSynced(documents.deletingLastPathComponent()) {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("DocuDesk", isDirectory: true)
        }
        return documents
    }

    static func chooseFolder(message: String, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: BackupService.fileExtension) ?? .zip, .zip]
        panel.message = "Choose a DocuDesk backup (.\(BackupService.fileExtension))"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - First run

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var taxID = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = Address(country: "India")
    @State private var currency = "INR"
    @State private var taxSplit: TaxSplit = .cgstSgst
    @State private var taxRate: Decimal = 18
    @State private var location = StorageLocation.recommendedDefault
    @State private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            hero
                .frame(width: 420)
            // Scroll only when the window is too short for the form.
            ViewThatFits(in: .vertical) {
                paddedForm
                ScrollView(.vertical) { paddedForm }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer()
            LogoMark(size: 64)
            VStack(alignment: .leading, spacing: 10) {
                Text("Welcome to DocuDesk").font(.system(size: 32, weight: .bold))
                Text("Create invoices, quotations and business documents on your Mac. No account, no internet required.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("wifi.slash", "Works fully offline", "Everything is created and saved on this Mac.")
                feature("folder", "Files you can see", "Every document lives in an ordinary folder in Finder.")
                feature("lock.shield", "Issued means issued", "Issued documents are locked and revised, never silently rewritten.")
                feature("externaldrive.badge.checkmark", "Verified backups", "Back up to any drive and restore with checksum verification.")
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(44)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0x1554D8), Color(hex: 0x3B82F6), Color(hex: 0x6366F1)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var paddedForm: some View {
        form
            .frame(maxWidth: 620)
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your workspace").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
                Text("These details appear on your documents. You can change them later in Settings.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your business").font(.system(size: 14, weight: .semibold))
                    LabeledField(label: "Business name *") { TextField("e.g. Shree Tech", text: $name).fieldStyle() }
                    HStack(spacing: 12) {
                        LabeledField(label: "GSTIN / tax ID") { TextField("Optional", text: $taxID).fieldStyle() }
                        LabeledField(label: "Phone") { TextField("Optional", text: $phone).fieldStyle() }
                    }
                    LabeledField(label: "Email") { TextField("Optional", text: $email).fieldStyle() }
                    AddressFields(title: "Address", address: $address)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Defaults").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 12) {
                        LabeledField(label: "Currency") {
                            Picker("", selection: $currency) {
                                ForEach(CurrencyInfo.supported) { Text("\($0.code) · \($0.name)").tag($0.code) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Tax") {
                            Picker("", selection: $taxSplit) {
                                ForEach(TaxSplit.allCases) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                        }
                        LabeledField(label: "Default rate %") {
                            DecimalField(placeholder: "18", value: $taxRate).fieldStyle().frame(width: 80)
                        }
                    }
                    Text("Rates are set per line item; nothing assumes one rate for every transaction.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage folder").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        Text(location.path).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Change…") {
                            if let folder = StorageLocation.chooseFolder(message: "Choose where DocuDesk keeps its folder") {
                                location = Workspace.isWorkspace(folder) ? folder : folder.appendingPathComponent("DocuDesk", isDirectory: true)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    if StorageLocation.isCloudSynced(location) {
                        Label("This folder is synced by iCloud Drive. Sync can corrupt the local database; a folder outside iCloud is recommended.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.warning)
                    } else {
                        Label("Documents, PDFs and backups are kept here as normal files.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.success)
                    }
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.danger)
            }

            HStack {
                Button("Open Existing Workspace…") {
                    if let folder = StorageLocation.chooseFolder(message: "Choose an existing DocuDesk folder", prompt: "Open") {
                        model.open(folder)
                    }
                }
                .buttonStyle(.link)
                Spacer()
                Button("Create Workspace") { create() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func create() {
        var profile = CompanyProfile(name: name.trimmingCharacters(in: .whitespaces))
        profile.taxID = taxID
        profile.taxIDLabel = currency == "INR" ? "GSTIN" : "Tax ID"
        profile.email = email
        profile.phone = phone
        profile.address = address
        profile.defaultCurrency = currency
        profile.defaultTaxSplit = taxSplit
        profile.defaultTaxRate = taxRate
        profile.defaultTerms = "1. Payment is due within \(profile.defaultPaymentTermsDays) days.\n2. Please quote the invoice number with your payment."
        do {
            try model.createWorkspace(at: location, profile: profile)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Storage problems

struct StorageProblemView: View {
    let problem: WorkspaceProblem
    @EnvironmentObject private var model: AppModel
    @State private var error: String?

    var body: some View {
        VStack {
            Card(padding: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.warning)
                    Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
                    Text(message).font(.system(size: 13.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(problem.path)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
                    if let error {
                        Label(error, systemImage: "exclamationmark.octagon.fill").font(.system(size: 12.5)).foregroundStyle(Theme.danger)
                    }
                    actions
                    Text("DocuDesk never creates an empty replacement database on its own.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 620)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private var icon: String {
        switch problem {
        case .missing: "externaldrive.badge.xmark"
        case .moved: "arrow.right.doc.on.clipboard"
        case .databaseMissing: "cylinder.split.1x2"
        case .other: "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch problem {
        case .missing: "Your DocuDesk folder isn’t available"
        case .moved: "Your DocuDesk folder has moved"
        case .databaseMissing: "The workspace database is missing"
        case .other: "The workspace couldn’t be opened"
        }
    }

    private var message: String {
        switch problem {
        case .missing:
            "If it’s on an external drive, connect the drive and choose Try Again. If you moved it, locate it. Nothing has been changed."
        case let .moved(_, to):
            "DocuDesk found it at “\(to)”. Use the new location?"
        case .databaseMissing:
            "Your document files are still in the folder. Restoring a backup brings back clients, products and settings too. Rebuilding re-indexes documents from their files; clients and products will need to be re-entered."
        case let .other(_, message):
            message
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch problem {
            case let .moved(_, to):
                Button("Use New Location") { model.open(URL(fileURLWithPath: to)) }.buttonStyle(PrimaryButtonStyle())
            case .databaseMissing:
                Button("Restore from Backup…") { restore() }.buttonStyle(PrimaryButtonStyle())
                Button("Rebuild from Document Files") { model.open(URL(fileURLWithPath: problem.path), recreateDatabase: true) }
                    .buttonStyle(SecondaryButtonStyle())
            default:
                Button("Try Again") { model.open(URL(fileURLWithPath: problem.path)) }.buttonStyle(PrimaryButtonStyle())
            }
            Button("Locate Folder…") {
                if let folder = StorageLocation.chooseFolder(message: "Locate your DocuDesk folder", prompt: "Open") {
                    model.open(folder)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button("Create New Workspace") { model.startOver() }.buttonStyle(.link)
        }
    }

    private func restore() {
        guard let backup = StorageLocation.chooseBackup() else { return }
        var password: String?
        if BackupCrypto.isEncrypted(backup) {
            guard let entered = askForPassword(message: "This backup is encrypted. Enter its password.") else { return }
            password = entered
        }
        do {
            try BackupService.restore(backup, intoWorkspaceAt: URL(fileURLWithPath: problem.path), password: password)
            model.open(URL(fileURLWithPath: problem.path))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
