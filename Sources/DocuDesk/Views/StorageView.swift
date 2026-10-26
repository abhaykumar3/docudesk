import DocuDeskCore
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var history: [BackupRecord] = []
    @State private var documentCount = 0
    @State private var integrityOK: Bool?
    @State private var maintenanceMessage: String?
    @State private var damaged: [(path: String, reason: String)] = []
    @State private var confirmRestore: URL?
    @State private var settingPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Offline Storage", subtitle: "Everything DocuDesk stores lives in one folder on this Mac. Nothing is uploaded.")
                if let store = model.store {
                    locationCard(store)
                    HStack(alignment: .top, spacing: 16) {
                        foldersCard(store)
                        maintenanceCard(store)
                    }
                    backupCard(store)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
        }
        .task(id: model.revision) { load() }
        .sheet(isPresented: $settingPassword) { EncryptionSetupSheet() }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } })) {
            Button("Restore", role: .destructive) {
                if let url = confirmRestore { model.restore(from: url) }
            }
        } message: {
            Text("Your current documents, clients and settings will be replaced by the backup. They’re moved aside into the Backups folder first, not deleted.")
        }
    }

    private func load() {
        guard let store = model.store else { return }
        history = BackupService.history(of: store)
        documentCount = (try? store.documentCount()) ?? 0
    }

    private func locationCard(_ store: WorkspaceStore) -> some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.success)
                    .frame(width: 52, height: 52)
                    .background(Theme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace folder").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text(store.workspace.root.path).font(.system(size: 14, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Text("\(documentCount) documents · Created \(store.manifest.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    if StorageLocation.isCloudSynced(store.workspace.root) {
                        Label("This folder is synced by iCloud Drive, which can corrupt the database. Consider moving it outside iCloud.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.warning)
                    }
                }
                Spacer()
                Button("Show in Finder") { model.revealInFinder(store.workspace.root) }.buttonStyle(SecondaryButtonStyle())
                Button("Open Another…") {
                    if let folder = StorageLocation.chooseFolder(message: "Choose a DocuDesk workspace folder", prompt: "Open") {
                        model.activeEditor?.flushPendingSave()
                        model.open(folder)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func foldersCard(_ store: WorkspaceStore) -> some View {
        let folders: [(String, String, URL)] = [
            ("Documents", "Editable records and exported PDFs, by type and year", store.workspace.documentsURL),
            ("Database", "Search index, clients, products and settings", store.workspace.databaseFolder),
            ("Assets", "Logos and signatures", store.workspace.assetsURL),
            ("Backups", "Backup packages", store.workspace.backupsURL),
            ("Exports", "Your own exported copies", store.workspace.exportsURL),
        ]
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Folders")
                ForEach(folders, id: \.0) { name, detail, url in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").foregroundStyle(Color(hex: 0x3B82F6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.system(size: 13, weight: .medium))
                            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button { model.revealInFinder(url) } label: { Image(systemName: "arrow.up.forward.square") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .help("Show in Finder")
                    }
                }
            }
        }
    }

    private func maintenanceCard(_ store: WorkspaceStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Maintenance", subtitle: "Check and repair the local index")
                HStack(spacing: 10) {
                    Button("Check Integrity") {
                        integrityOK = (try? store.database.integrityCheck()) ?? false
                        let missing = (try? store.missingDocumentFiles()) ?? []
                        maintenanceMessage = missing.isEmpty
                            ? "All indexed documents have their files."
                            : "\(missing.count) indexed document(s) are missing their files: \(missing.prefix(3).map(\.number).joined(separator: ", ")). Rebuild the index to resync."
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Rebuild Index") {
                        do {
                            let report = try store.rebuildIndex()
                            damaged = report.damaged
                            maintenanceMessage = "Indexed \(report.indexed) document(s)." + (report.damaged.isEmpty ? "" : " \(report.damaged.count) file(s) need attention.")
                            model.refresh()
                        } catch {
                            model.show(error, title: "Rebuild failed")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if let integrityOK {
                    Label(integrityOK ? "Database integrity check passed" : "Database integrity check failed. Restore a backup or rebuild the index.",
                          systemImage: integrityOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(integrityOK ? Theme.success : Theme.danger)
                }
                if let maintenanceMessage {
                    Text(maintenanceMessage).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                }
                ForEach(damaged, id: \.path) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.path).font(.system(size: 11.5, design: .monospaced))
                        Text(item.reason).font(.system(size: 11)).foregroundStyle(Theme.danger)
                    }
                }
                Text("Rebuilding reads every document.json. Damaged files are reported and left untouched.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func backupCard(_ store: WorkspaceStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Backup & Restore", subtitle: model.lastBackup.map { "Last backup \($0.relativeDescription)" } ?? "No backups yet") {
                    HStack(spacing: 10) {
                        Button("Restore…") {
                            if let url = StorageLocation.chooseBackup() { confirmRestore = url }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button("Back Up To…") {
                            if let folder = StorageLocation.chooseFolder(message: "Choose a folder or external drive for the backup", prompt: "Back Up") {
                                model.backUp(to: folder)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.backupInProgress)
                        Button(model.backupInProgress ? "Backing Up…" : "Back Up Now") { model.backUp(to: nil) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.backupInProgress)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: model.encryptBackups ? "lock.fill" : "lock.open").foregroundStyle(model.encryptBackups ? Theme.success : Theme.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.encryptBackups ? "Backups are encrypted (AES-256)" : "Backups are not encrypted").font(.system(size: 12.5, weight: .semibold))
                        Text(model.encryptBackups
                             ? "The password is stored in your Mac’s Keychain. Without it, encrypted backups can’t be restored on another Mac."
                             : "Encrypt backups with a password before copying them to external drives or cloud folders.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if model.encryptBackups {
                        Button("Turn Off") { model.disableEncryption() }.buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button("Encrypt Backups…") { settingPassword = true }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(12)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 24) {
                    Toggle("Automatic backups", isOn: setting(.autoBackupEnabled, default: true))
                    Stepper("Every \(model.autoBackupIntervalDays) day\(model.autoBackupIntervalDays == 1 ? "" : "s")",
                            value: intSetting(.autoBackupIntervalDays, default: 7), in: 1...30)
                    Stepper("Keep \(model.backupRetention) automatic backups", value: intSetting(.backupRetentionCount, default: 10), in: 1...60)
                }
                .font(.system(size: 12.5))

                if history.isEmpty {
                    Text("Backups include documents, PDFs, logos, clients, products, numbering and settings. Each one is checksummed and read back before it’s marked verified.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(history.prefix(10)) { record in
                            HStack(spacing: 12) {
                                Image(systemName: record.verified ? "checkmark.shield.fill" : "shield")
                                    .foregroundStyle(record.verified ? Theme.success : Theme.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(URL(fileURLWithPath: record.path).lastPathComponent).font(.system(size: 12.5, weight: .medium))
                                    Text(URL(fileURLWithPath: record.path).deletingLastPathComponent().path)
                                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if record.encrypted {
                                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.secondary).help("Encrypted")
                                }
                                if record.automatic {
                                    Text("Auto").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary)
                                }
                                Text(ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file))
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12))
                                let exists = FileManager.default.fileExists(atPath: record.path)
                                Button(exists ? "Restore" : "Unavailable") { confirmRestore = URL(fileURLWithPath: record.path) }
                                    .buttonStyle(.link)
                                    .disabled(!exists)
                            }
                            .padding(.vertical, 8)
                            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func setting(_ key: WorkspaceStore.SettingKey, default value: Bool) -> Binding<Bool> {
        Binding(
            get: { model.store?.setting(key).map { $0 == "true" } ?? value },
            set: {
                try? model.store?.setSetting(key, $0 ? "true" : "false")
                model.refresh()
            }
        )
    }

    private func intSetting(_ key: WorkspaceStore.SettingKey, default value: Int) -> Binding<Int> {
        Binding(
            get: { model.store?.setting(key).flatMap(Int.init) ?? value },
            set: {
                try? model.store?.setSetting(key, String($0))
                model.refresh()
            }
        )
    }
}

private struct EncryptionSetupSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var understood = false

    private var valid: Bool { password.count >= 8 && password == confirm && understood }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Encrypt Backups", systemImage: "lock.shield").font(.system(size: 18, weight: .bold))
            Text("New backups will be encrypted with AES-256-GCM using a key derived from this password. Existing backups stay as they are.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            LabeledField(label: "Password (at least 8 characters)") { SecureField("", text: $password).fieldStyle() }
            LabeledField(label: "Confirm password") { SecureField("", text: $confirm).fieldStyle() }
            if !confirm.isEmpty, password != confirm {
                Text("The passwords don’t match.").font(.system(size: 11.5)).foregroundStyle(Theme.danger)
            }
            Toggle("I understand that if I lose this password, encrypted backups cannot be recovered by anyone.", isOn: $understood)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Turn On Encryption") {
                    model.enableEncryption(password: password)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!valid)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
