import AppKit
import DocuDeskCore
import SwiftUI

enum Screen: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case documents
    case templates
    case clients
    case products
    case reports
    case storage
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .documents: "Documents"
        case .templates: "Templates"
        case .clients: "Clients"
        case .products: "Products & Services"
        case .reports: "Reports"
        case .storage: "Offline Storage"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "house"
        case .documents: "doc.text"
        case .templates: "rectangle.on.rectangle"
        case .clients: "person.2"
        case .products: "cart"
        case .reports: "chart.bar"
        case .storage: "externaldrive"
        case .settings: "gearshape"
        }
    }
}

enum WorkspaceProblem: Equatable {
    case missing(path: String)
    case moved(from: String, to: String)
    case databaseMissing(path: String)
    case other(path: String, message: String)

    var path: String {
        switch self {
        case let .missing(path), let .databaseMissing(path), let .other(path, _): path
        case let .moved(from, _): from
        }
    }
}

enum AppPhase: Equatable {
    case loading
    case setup
    case problem(WorkspaceProblem)
    case ready
}

struct StarterRequest: Identifiable {
    let id = UUID()
    let kind: DocumentKind
    let templateID: String?
    let customer: Customer?
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .loading
    @Published private(set) var store: WorkspaceStore?
    @Published var profile: CompanyProfile?
    @Published private(set) var profiles: [CompanyProfile] = []
    @Published private(set) var customTypes: [CustomDocumentType] = []
    /// Set when a text document is being created and its starter content must be chosen.
    @Published var starterRequest: StarterRequest?
    @Published var screen: Screen = .dashboard
    /// Document open in the editor; replaces the current screen's content while set.
    @Published var openDocumentID: UUID?
    @Published var searchText = ""
    @Published private(set) var searchFocusRequest = 0
    @Published var alert: AppAlert?
    @Published var toast: String?
    @Published var backupInProgress = false
    /// Bumped after any change so lists reload.
    @Published private(set) var revision = 0

    weak var activeEditor: DocumentEditorModel?

    private let defaults = UserDefaults.standard
    private let pathKey = "workspacePath"
    private let bookmarkKey = "workspaceBookmark"

    // MARK: Launch

    func start() {
        guard let path = defaults.string(forKey: pathKey) else {
            phase = .setup
            #if DEBUG
            runSnapshotScriptIfRequested()
            #endif
            return
        }
        open(URL(fileURLWithPath: path))
    }

    func open(_ url: URL, recreateDatabase: Bool = false) {
        store?.close()
        store = nil
        do {
            let opened = try WorkspaceStore.open(at: url, recreateDatabase: recreateDatabase)
            adopt(opened)
        } catch let error as WorkspaceError {
            switch error {
            case .folderMissing:
                if let moved = resolveMovedWorkspace(), moved.path != url.path {
                    phase = .problem(.moved(from: url.path, to: moved.path))
                } else {
                    phase = .problem(.missing(path: url.path))
                }
            case .databaseMissing:
                phase = .problem(.databaseMissing(path: url.path))
            default:
                phase = .problem(.other(path: url.path, message: error.localizedDescription))
            }
        } catch {
            phase = .problem(.other(path: url.path, message: error.localizedDescription))
        }
    }

    func createWorkspace(at url: URL, profile: CompanyProfile) throws {
        let created = try WorkspaceStore.create(at: url, profile: profile)
        adopt(created)
    }

    private func adopt(_ opened: WorkspaceStore) {
        store = opened
        defaults.set(opened.workspace.root.path, forKey: pathKey)
        if let bookmark = try? opened.workspace.root.bookmarkData() {
            defaults.set(bookmark, forKey: bookmarkKey)
        }
        profile = try? opened.defaultProfile()
        profiles = (try? opened.profiles()) ?? []
        customTypes = (try? opened.customTypes()) ?? []
        phase = .ready
        revision += 1
        runAutomaticBackupIfDue()
        #if DEBUG
        runSnapshotScriptIfRequested()
        #endif
    }

    /// If the folder was renamed or moved in Finder, the bookmark still finds it.
    private func resolveMovedWorkspace() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
              Workspace.isWorkspace(url) else { return nil }
        return url
    }

    func startOver() {
        store?.close()
        store = nil
        phase = .setup
    }

    // MARK: Changes

    func refresh() {
        if let store {
            profile = try? store.defaultProfile()
            profiles = (try? store.profiles()) ?? []
            customTypes = (try? store.customTypes()) ?? []
        }
        revision += 1
    }

    /// New documents use the active profile's details, numbering and folder.
    func switchProfile(to id: UUID) {
        do {
            try store?.setActiveProfile(id)
            refresh()
            flash("Now working as \(profile?.name ?? "")")
        } catch {
            show(error)
        }
    }

    func show(_ error: Error, title: String = "Something went wrong") {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    func flash(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if self.toast == message { self.toast = nil }
        }
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func navigate(to screen: Screen) {
        openDocumentID = nil
        self.screen = screen
    }

    // MARK: Documents

    func createDocument(_ kind: DocumentKind, templateID: String? = nil, customer: Customer? = nil, starter: DocumentStarter? = nil) {
        guard let store else { return }
        if kind.usesBody, starter == nil {
            starterRequest = StarterRequest(kind: kind, templateID: templateID, customer: customer)
            return
        }
        do {
            let document = try store.newDocument(kind: kind, profileID: profile?.id, templateID: templateID, customer: customer, starter: starter)
            refresh()
            openDocumentID = document.id
        } catch {
            show(error, title: "Couldn’t create the document")
        }
    }

    func createDocument(customType: CustomDocumentType, customer: Customer? = nil) {
        guard let store else { return }
        do {
            let document = try store.newDocument(customType: customType, profileID: profile?.id, customer: customer)
            refresh()
            openDocumentID = document.id
        } catch {
            show(error, title: "Couldn’t create the document")
        }
    }

    func openDocument(_ id: UUID) {
        activeEditor?.flushPendingSave()
        store?.noteOpened(id)
        openDocumentID = id
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Backups

    var lastBackup: Date? {
        store.flatMap { BackupService.lastBackupDate(of: $0) }
    }

    var autoBackupIntervalDays: Int {
        store?.setting(.autoBackupIntervalDays).flatMap(Int.init) ?? 7
    }

    var autoBackupEnabled: Bool {
        store?.setting(.autoBackupEnabled) != "false"
    }

    var backupRetention: Int {
        store?.setting(.backupRetentionCount).flatMap(Int.init) ?? 10
    }

    var backupIsStale: Bool {
        guard let lastBackup else { return true }
        return Date().timeIntervalSince(lastBackup) > Double(autoBackupIntervalDays) * 86_400
    }

    func runAutomaticBackupIfDue() {
        guard let store, autoBackupEnabled, backupIsStale else { return }
        guard (try? store.search(DocumentQuery()).isEmpty) == false else { return }
        backUp(to: nil, automatic: true)
    }

    var encryptBackups: Bool {
        store?.setting(.encryptBackups) == "true"
    }

    /// Turns on encrypted backups; the password is kept in the Keychain so automatic backups work.
    func enableEncryption(password: String) {
        guard let store else { return }
        do {
            try BackupKeychain.save(password, workspaceID: store.manifest.id)
            try store.setSetting(.encryptBackups, "true")
            revision += 1
            flash("Backups will be encrypted")
        } catch {
            show(error, title: "Couldn’t turn on encryption")
        }
    }

    func disableEncryption() {
        guard let store else { return }
        BackupKeychain.delete(workspaceID: store.manifest.id)
        try? store.setSetting(.encryptBackups, "false")
        revision += 1
    }

    func backUp(to directory: URL?, automatic: Bool = false) {
        guard let store, !backupInProgress else { return }
        var password: String?
        if encryptBackups {
            password = BackupKeychain.load(workspaceID: store.manifest.id)
            if password == nil {
                if !automatic {
                    alert = AppAlert(title: "Backup password missing",
                                     message: "Encryption is on but the password isn’t in the Keychain. Turn encryption off and on again in Offline Storage to set it.")
                }
                return
            }
        }
        backupInProgress = true
        let destination = directory ?? store.workspace.backupsURL
        let retention = backupRetention
        Task.detached(priority: .utility) {
            let result = Result { try BackupService.createBackup(of: store, in: destination, automatic: automatic, password: password) }
            if automatic { BackupService.applyRetention(to: store, keep: retention) }
            await MainActor.run {
                self.backupInProgress = false
                switch result {
                case .success: self.flash(automatic ? "Automatic backup completed" : "Backup created and verified")
                case let .failure(error): self.show(error, title: "Backup failed")
                }
                self.revision += 1
            }
        }
    }

    func restore(from url: URL) {
        guard let store else { return }
        let root = store.workspace.root
        var password: String?
        if BackupCrypto.isEncrypted(url) {
            // Try this workspace's saved password first, then ask.
            if let saved = BackupKeychain.load(workspaceID: store.manifest.id),
               let checked = try? BackupService.verify(url, password: saved) {
                try? FileManager.default.removeItem(at: checked.extractedRoot.deletingLastPathComponent())
                password = saved
            } else if let entered = askForPassword(message: "“\(url.lastPathComponent)” is encrypted. Enter its password to restore it.") {
                password = entered
            } else {
                return
            }
        }
        do {
            let checked = try BackupService.verify(url, password: password)
            try? FileManager.default.removeItem(at: checked.extractedRoot.deletingLastPathComponent())
        } catch {
            show(error, title: "This backup can’t be restored")
            return
        }
        openDocumentID = nil
        store.close()
        self.store = nil
        do {
            let safety = try BackupService.restore(url, intoWorkspaceAt: root, password: password)
            open(root)
            flash("Restored. Previous data kept in \(safety.lastPathComponent)")
        } catch {
            open(root)
            show(error, title: "Restore failed; your previous data was put back")
        }
    }
}
