import AppKit
import Foundation

public struct DocumentSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: DocumentKind
    public let number: String
    public let title: String
    public let status: DocumentStatus
    public let customerName: String
    public let customerID: UUID?
    public let issueDate: CalendarDate
    public let dueDate: CalendarDate?
    public let currency: String
    public let total: Decimal
    public let balance: Decimal
    public let relativePath: String
    public let updatedAt: Date
    public let lastExportPath: String?
    public let lastExportedAt: Date?
    public let tags: [String]
    public let pinned: Bool
    public let archived: Bool
    public let profileID: UUID?
    /// "Invoice", or a custom type's name.
    public let typeName: String
    public let typeKey: String

    public var isOverdue: Bool {
        guard kind == .invoice, status.isOutstanding, let dueDate else { return false }
        return dueDate < .today && balance > 0
    }

    /// Stored status, with overdue invoices surfaced even if nobody updated them.
    public var effectiveStatus: DocumentStatus { isOverdue ? .overdue : status }
}

public struct DocumentQuery: Codable, Hashable, Sendable {
    public var text: String = ""
    public var kinds: Set<DocumentKind> = []
    public var statuses: Set<DocumentStatus> = []
    public var customerID: UUID?
    public var profileID: UUID?
    /// Restricts to one custom document type.
    public var customTypeID: UUID?
    public var from: CalendarDate?
    public var to: CalendarDate?
    public var minAmount: Decimal?
    public var maxAmount: Decimal?
    /// Every tag must be present.
    public var tags: Set<String> = []
    public var pinnedOnly = false
    /// Archived documents are hidden unless asked for.
    public var archive: ArchiveFilter = .active
    public var limit: Int = 5000

    public enum ArchiveFilter: String, Codable, CaseIterable, Sendable {
        case active
        case archived
        case all
    }

    public init() {}
}

public struct RebuildReport: Sendable {
    public var indexed: Int = 0
    public var damaged: [(path: String, reason: String)] = []
}

public struct CurrencyAmount: Hashable, Sendable, Identifiable {
    public let currency: String
    public let amount: Decimal
    public var id: String { currency }
}

public struct DashboardStats: Sendable {
    public var counts: [DocumentKind: Int] = [:]
    public var drafts: Int = 0
    public var invoiced: [CurrencyAmount] = []
    public var outstanding: [CurrencyAmount] = []
    public var overdue: [CurrencyAmount] = []
    public var paid: [CurrencyAmount] = []
    public var overdueCount: Int = 0
    public var recent: [DocumentSummary] = []
    public var recentExports: [DocumentSummary] = []

    public var total: Int { counts.values.reduce(0, +) }

    public init() {}
}

/// Central access to a workspace: the SQLite index plus JSON document files.
/// UI code goes through this type instead of touching files directly.
public final class WorkspaceStore {
    public let workspace: Workspace
    public let database: SQLiteDatabase
    public let manifest: WorkspaceManifest
    private let fileManager = FileManager.default

    public static let schemaVersion = 3

    private init(workspace: Workspace, database: SQLiteDatabase, manifest: WorkspaceManifest) {
        self.workspace = workspace
        self.database = database
        self.manifest = manifest
    }

    // MARK: Opening and creating

    /// Creates a new workspace. Refuses to take over a folder that already holds a different workspace.
    public static func create(at root: URL, profile: CompanyProfile) throws -> WorkspaceStore {
        let workspace = Workspace(root: root)
        let fileManager = FileManager.default
        if Workspace.isWorkspace(root) {
            return try open(at: root)
        }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            for folder in workspace.standardFolders {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            for kind in DocumentKind.builtIn {
                try fileManager.createDirectory(at: workspace.documentsURL.appendingPathComponent(kind.folderName), withIntermediateDirectories: true)
            }
            let manifest = WorkspaceManifest(id: UUID(), formatVersion: Workspace.formatVersion, createdAt: Date(), createdBy: "DocuDesk for Mac")
            try DocuDeskJSON.encoder.encode(manifest).write(to: workspace.manifestURL, options: .atomic)
        } catch {
            throw WorkspaceError.notWritable(root.path)
        }
        let store = try open(at: root, recreateDatabase: true)
        try store.saveProfile(profile)
        try store.setSetting(.defaultProfileID, profile.id.uuidString)
        try store.setSetting(.primaryProfileID, profile.id.uuidString)
        return store
    }

    /// Opens an existing workspace. Never silently creates an empty database: a missing database
    /// is reported unless the caller explicitly asks to recreate it.
    public static func open(at root: URL, recreateDatabase: Bool = false) throws -> WorkspaceStore {
        let workspace = Workspace(root: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError.folderMissing(root.path)
        }
        guard let data = try? Data(contentsOf: workspace.manifestURL),
              let manifest = try? DocuDeskJSON.decoder.decode(WorkspaceManifest.self, from: data)
        else {
            throw WorkspaceError.notAWorkspace(root.path)
        }
        guard manifest.formatVersion <= Workspace.formatVersion else {
            throw WorkspaceError.unsupportedFormat(manifest.formatVersion)
        }
        let databaseExists = FileManager.default.fileExists(atPath: workspace.databaseURL.path)
        if !databaseExists && !recreateDatabase {
            throw WorkspaceError.databaseMissing(root.path)
        }
        try? FileManager.default.createDirectory(at: workspace.databaseFolder, withIntermediateDirectories: true)
        let database = try SQLiteDatabase(url: workspace.databaseURL, create: recreateDatabase)
        let store = WorkspaceStore(workspace: workspace, database: database, manifest: manifest)
        try store.migrate()
        if !databaseExists {
            _ = try store.rebuildIndex()
        }
        return store
    }

    public func close() {
        database.close()
    }

    private func migrate() throws {
        let version = database.userVersion
        guard version < Self.schemaVersion else { return }
        try database.transaction {
            if version < 1 {
                try database.execute("""
                CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS profiles (id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS customers (id TEXT PRIMARY KEY, name TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS products (id TEXT PRIMARY KEY, name TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS documents (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    number TEXT NOT NULL,
                    title TEXT NOT NULL,
                    status TEXT NOT NULL,
                    profile_id TEXT NOT NULL,
                    customer_id TEXT,
                    customer_name TEXT NOT NULL,
                    issue_date TEXT NOT NULL,
                    due_date TEXT,
                    currency TEXT NOT NULL,
                    total TEXT NOT NULL,
                    total_minor INTEGER NOT NULL,
                    balance_minor INTEGER NOT NULL,
                    revision INTEGER NOT NULL,
                    rel_path TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_export_path TEXT,
                    last_exported_at TEXT
                );
                CREATE UNIQUE INDEX IF NOT EXISTS documents_number ON documents(profile_id, kind, number);
                CREATE INDEX IF NOT EXISTS documents_issue_date ON documents(issue_date);
                CREATE INDEX IF NOT EXISTS documents_status ON documents(status);
                CREATE INDEX IF NOT EXISTS documents_customer ON documents(customer_id);
                CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(id UNINDEXED, number, title, customer, body, tokenize = 'unicode61');
                CREATE TABLE IF NOT EXISTS backups (id TEXT PRIMARY KEY, path TEXT NOT NULL, created_at TEXT NOT NULL, verified INTEGER NOT NULL, automatic INTEGER NOT NULL, size INTEGER NOT NULL);
                """)
            }
            if version < 2 {
                try addColumn("documents", "tags", "TEXT NOT NULL DEFAULT ''")
                try addColumn("documents", "pinned", "INTEGER NOT NULL DEFAULT 0")
                try addColumn("documents", "archived", "INTEGER NOT NULL DEFAULT 0")
                try database.execute("""
                CREATE INDEX IF NOT EXISTS documents_archived ON documents(archived);
                CREATE TABLE IF NOT EXISTS clauses (id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, json TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS custom_templates (id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL, updated_at TEXT NOT NULL);
                """)
            }
            if version < 3 {
                try addColumn("documents", "type_key", "TEXT NOT NULL DEFAULT ''")
                try addColumn("documents", "type_name", "TEXT NOT NULL DEFAULT ''")
                try addColumn("backups", "encrypted", "INTEGER NOT NULL DEFAULT 0")
                try database.execute("""
                UPDATE documents SET type_key = kind WHERE type_key = '';
                CREATE INDEX IF NOT EXISTS documents_type ON documents(type_key);
                CREATE TABLE IF NOT EXISTS custom_types (id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL, updated_at TEXT NOT NULL);
                """)
            }
            try database.setUserVersion(Self.schemaVersion)
        }
    }

    /// `ALTER TABLE … ADD COLUMN` that is a no-op when the column already exists, so a migration
    /// interrupted part-way can simply run again.
    private func addColumn(_ table: String, _ column: String, _ definition: String) throws {
        let existing = try database.query("PRAGMA table_info(\(table))").compactMap { $0.string("name") }
        guard !existing.contains(column) else { return }
        try database.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    // MARK: Settings

    public enum SettingKey: String {
        case defaultProfileID
        case favoriteTemplates
        case autoBackupEnabled
        case autoBackupIntervalDays
        case backupRetentionCount
        case backupDestination
        case clausesSeeded
        case savedFilters
        case recentDocuments
        case primaryProfileID
        case encryptBackups
    }

    public func setting(_ key: SettingKey) -> String? {
        try? database.query("SELECT value FROM settings WHERE key = ?", [.text(key.rawValue)]).first?.string("value")
    }

    public func setSetting(_ key: SettingKey, _ value: String?) throws {
        if let value {
            try database.run("INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key.rawValue), .text(value)])
        } else {
            try database.run("DELETE FROM settings WHERE key = ?", [.text(key.rawValue)])
        }
    }

    public var favoriteTemplateIDs: Set<String> {
        get {
            guard let raw = setting(.favoriteTemplates), let data = raw.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(ids)
        }
    }

    public func setFavoriteTemplateIDs(_ ids: Set<String>) throws {
        let data = try JSONEncoder().encode(ids.sorted())
        try setSetting(.favoriteTemplates, String(decoding: data, as: UTF8.self))
    }

    // MARK: Profiles, customers, products

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try DocuDeskJSON.encoder.encode(value), as: UTF8.self)
    }

    private func decodeRows<T: Decodable>(_ rows: [SQLRow], as type: T.Type) -> [T] {
        rows.compactMap { row in
            guard let json = row.string("json"), let data = json.data(using: .utf8) else { return nil }
            return try? DocuDeskJSON.decoder.decode(T.self, from: data)
        }
    }

    static let timestamp = ISO8601DateFormatter()

    // Tags are stored as `|a|b|` so a LIKE on `%|tag|%` matches whole tags only.
    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: "") }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func encodeTags(_ tags: [String]) -> String {
        tags.isEmpty ? "" : "|" + tags.joined(separator: "|") + "|"
    }

    static func decodeTags(_ value: String) -> [String] {
        value.split(separator: "|").map(String.init)
    }

    static func likeEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    public func profiles() throws -> [CompanyProfile] {
        decodeRows(try database.query("SELECT json FROM profiles ORDER BY name COLLATE NOCASE"), as: CompanyProfile.self)
    }

    public func profile(id: UUID) throws -> CompanyProfile? {
        decodeRows(try database.query("SELECT json FROM profiles WHERE id = ?", [.text(id.uuidString)]), as: CompanyProfile.self).first
    }

    public func defaultProfile() throws -> CompanyProfile? {
        if let raw = setting(.defaultProfileID), let id = UUID(uuidString: raw), let profile = try profile(id: id) {
            return profile
        }
        return try profiles().first
    }

    public func saveProfile(_ profile: CompanyProfile) throws {
        var profile = profile
        profile.updatedAt = Date()
        try database.run(
            "INSERT INTO profiles(id, name, json, updated_at) VALUES(?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, json = excluded.json, updated_at = excluded.updated_at",
            [.text(profile.id.uuidString), .text(profile.name), .text(try encode(profile)), .text(Self.timestamp.string(from: profile.updatedAt))]
        )
    }

    public func customers(includeArchived: Bool = false) throws -> [Customer] {
        let sql = includeArchived
            ? "SELECT json FROM customers ORDER BY name COLLATE NOCASE"
            : "SELECT json FROM customers WHERE archived = 0 ORDER BY name COLLATE NOCASE"
        return decodeRows(try database.query(sql), as: Customer.self)
    }

    public func customer(id: UUID) throws -> Customer? {
        decodeRows(try database.query("SELECT json FROM customers WHERE id = ?", [.text(id.uuidString)]), as: Customer.self).first
    }

    public func saveCustomer(_ customer: Customer) throws {
        var customer = customer
        customer.updatedAt = Date()
        try database.run(
            "INSERT INTO customers(id, name, archived, json, updated_at) VALUES(?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, archived = excluded.archived, json = excluded.json, updated_at = excluded.updated_at",
            [.text(customer.id.uuidString), .text(customer.name), .int(customer.archived ? 1 : 0), .text(try encode(customer)), .text(Self.timestamp.string(from: customer.updatedAt))]
        )
    }

    public func documentCount(forCustomer id: UUID) throws -> Int {
        Int(try database.query("SELECT COUNT(*) AS n FROM documents WHERE customer_id = ?", [.text(id.uuidString)]).first?.int("n") ?? 0)
    }

    /// Deletes a customer only when no documents reference it; otherwise archive it instead.
    public func deleteCustomer(id: UUID) throws -> Bool {
        guard try documentCount(forCustomer: id) == 0 else { return false }
        try database.run("DELETE FROM customers WHERE id = ?", [.text(id.uuidString)])
        return true
    }

    public func products(includeArchived: Bool = false) throws -> [ProductService] {
        let sql = includeArchived
            ? "SELECT json FROM products ORDER BY name COLLATE NOCASE"
            : "SELECT json FROM products WHERE archived = 0 ORDER BY name COLLATE NOCASE"
        return decodeRows(try database.query(sql), as: ProductService.self)
    }

    public func saveProduct(_ product: ProductService) throws {
        var product = product
        product.updatedAt = Date()
        try database.run(
            "INSERT INTO products(id, name, archived, json, updated_at) VALUES(?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, archived = excluded.archived, json = excluded.json, updated_at = excluded.updated_at",
            [.text(product.id.uuidString), .text(product.name), .int(product.archived ? 1 : 0), .text(try encode(product)), .text(Self.timestamp.string(from: product.updatedAt))]
        )
    }

    public func deleteProduct(id: UUID) throws {
        try database.run("DELETE FROM products WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Assets

    /// Copies an image into `Assets/` and returns its workspace-relative path.
    public func importLogo(from source: URL, profileID: UUID) throws -> String {
        guard NSImage(contentsOf: source) != nil else { throw WorkspaceError.invalidImage }
        let ext = source.pathExtension.lowercased().isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "logo-\(profileID.uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let destination = workspace.assetsURL.appendingPathComponent(name)
        try fileManager.createDirectory(at: workspace.assetsURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
        return "Assets/\(name)"
    }

    public func image(at relativePath: String?) -> NSImage? {
        guard let relativePath, let url = try? workspace.resolve(relativePath) else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: Numbering

    /// Reserves the next number for `kind`, skipping any number already in use.
    public func allocateNumber(kind: DocumentKind, profileID: UUID, year: Int) throws -> String {
        try allocateNumber(key: kind.rawValue, defaultPrefix: kind.defaultPrefix, kind: kind, profileID: profileID, year: year)
    }

    /// Reserves the next number for a numbering sequence (`kind.rawValue` or `custom.<id>`).
    public func allocateNumber(key: String, defaultPrefix: String, kind: DocumentKind, profileID: UUID, year: Int) throws -> String {
        try database.transaction {
            guard var profile = try profile(id: profileID) else { throw WorkspaceError.recordNotFound }
            var rule = profile.numberingRule(forKey: key, defaultPrefix: defaultPrefix)
            var candidate = rule.candidate(for: year)
            var number = rule.format(candidate, year: year)
            while try numberExists(number, kind: kind, profileID: profileID, excluding: nil) {
                candidate += 1
                number = rule.format(candidate, year: year)
            }
            rule.nextNumber = candidate + 1
            rule.lastYear = year
            profile.numbering[key] = rule
            try saveProfile(profile)
            return number
        }
    }

    public func numberExists(_ number: String, kind: DocumentKind, profileID: UUID, excluding id: UUID?) throws -> Bool {
        let rows = try database.query(
            "SELECT id FROM documents WHERE profile_id = ? AND kind = ? AND number = ? COLLATE NOCASE AND id != ?",
            [.text(profileID.uuidString), .text(kind.rawValue), .text(number), .text(id?.uuidString ?? "")]
        )
        return !rows.isEmpty
    }

    static func validate(number: String) throws {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/:\\\0")
        guard !trimmed.isEmpty, trimmed == number, !number.hasPrefix("."), number.count <= 64,
              number.rangeOfCharacter(from: forbidden) == nil
        else { throw WorkspaceError.invalidNumber(number) }
    }

    // MARK: Documents

    public func newDocument(kind: DocumentKind, profileID: UUID? = nil, templateID: String? = nil, customer: Customer? = nil,
                            starter: DocumentStarter? = nil) throws -> DocumentRecord {
        guard let profile = try profileID.flatMap({ try self.profile(id: $0) }) ?? defaultProfile() else {
            throw WorkspaceError.recordNotFound
        }
        let template = try templateDefinition(id: templateID ?? profile.defaultTemplateID, kind: kind)
            ?? TemplateLibrary.defaultTemplate(for: kind, style: profile.defaultTemplateStyle)
        let today = CalendarDate.today
        let number = try allocateNumber(kind: kind, profileID: profile.id, year: today.year)
        var document = DocumentRecord(kind: kind, number: number, company: profile, template: template, issueDate: today)
        if let customer { apply(customer: customer, to: &document) }
        if kind.usesBody {
            let chosen = starter ?? DocumentStarter.starters(for: kind).first
            document.title = chosen?.title ?? ""
            document.body = RichTextBody(attributed: RichTextBuilder.build(chosen?.markup ?? "", theme: template.theme))
            document.notes = ""
            document.terms = ""
            document.paymentDetails = ""
        }
        if kind.usesLineItems {
            document.items = kind.usesBody ? [] : [LineItem(name: "", quantity: 1, unitPrice: 0, taxRate: profile.defaultTaxRate)]
        }
        return try save(document)
    }

    public func apply(customer: Customer, to document: inout DocumentRecord) {
        document.customerID = customer.id
        document.customer = customer.party
        if !customer.defaultCurrency.isEmpty { document.currency = customer.defaultCurrency }
        if document.kind == .invoice, let days = customer.paymentTermsDays {
            document.dueDate = document.issueDate.adding(days: days)
        }
    }

    public func folderPath(for document: DocumentRecord) -> String {
        let profileFolder = profileFolderName(for: document.profileID)
        let prefix = profileFolder.map { "Documents/\($0)" } ?? "Documents"
        return "\(prefix)/\(document.typeFolderName)/\(document.issueDate.year)/\(document.number)"
    }

    private func indexedPath(for id: UUID) throws -> String? {
        try database.query("SELECT rel_path FROM documents WHERE id = ?", [.text(id.uuidString)]).first?.string("rel_path")
    }

    public func documentFolder(for id: UUID) throws -> URL {
        guard let path = try indexedPath(for: id) else { throw WorkspaceError.recordNotFound }
        return try workspace.resolve(path)
    }

    public func loadDocument(id: UUID) throws -> DocumentRecord {
        let folder = try documentFolder(for: id)
        let url = folder.appendingPathComponent("document.json")
        guard let data = try? Data(contentsOf: url) else { throw WorkspaceError.recordNotFound }
        return try DocuDeskJSON.decoder.decode(DocumentRecord.self, from: data)
    }

    /// Saves a draft (or a status-only change). Issued content is protected: if the stored copy is
    /// locked and anything other than status, links or exports differs, the save is refused.
    @discardableResult
    public func save(_ document: DocumentRecord) throws -> DocumentRecord {
        if let stored = try? loadDocument(id: document.id), stored.status.isContentLocked {
            guard Self.sameContent(stored, document) else { throw WorkspaceError.documentLocked(stored.number) }
        }
        return try write(document)
    }

    static func sameContent(_ lhs: DocumentRecord, _ rhs: DocumentRecord) -> Bool {
        func normalized(_ record: DocumentRecord) -> DocumentRecord {
            var copy = record
            copy.status = .draft
            copy.links = []
            copy.exports = []
            copy.updatedAt = Date(timeIntervalSince1970: 0)
            copy.issuedAt = nil
            copy.totals = DocumentTotals()
            // Payments and organisation metadata can change after issue; content cannot.
            copy.payments = []
            copy.tags = []
            copy.pinned = false
            copy.archived = false
            copy.templateSnapshot = nil
            return copy
        }
        return normalized(lhs) == normalized(rhs)
    }

    @discardableResult
    private func write(_ document: DocumentRecord) throws -> DocumentRecord {
        var document = document
        try Self.validate(number: document.number)
        if try numberExists(document.number, kind: document.kind, profileID: document.profileID, excluding: document.id) {
            throw WorkspaceError.duplicateNumber(document.number)
        }
        document.totals = DocumentCalculator.totals(for: document)
        document.updatedAt = Date()
        document.tags = Self.normalizedTags(document.tags)
        if document.status == .draft, document.kind == .custom, let typeID = document.customType?.id,
           let current = try? customType(id: typeID) {
            document.customType = current
        }
        if document.status == .draft, let customID = CustomTemplate.id(from: document.templateID),
           let custom = try? customTemplate(id: customID) {
            document.templateVersion = custom.version
        }
        if document.status.isContentLocked, document.templateSnapshot == nil {
            document.templateSnapshot = theme(for: document)
        } else if document.status == .draft {
            document.templateSnapshot = nil
        }

        let newPath = folderPath(for: document)
        let newFolder = try workspace.resolve(newPath)
        let oldPath = try indexedPath(for: document.id)

        if let oldPath, oldPath != newPath {
            let oldFolder = try workspace.resolve(oldPath)
            if fileManager.fileExists(atPath: newFolder.path) { throw WorkspaceError.conflictingFolder(newPath) }
            try fileManager.createDirectory(at: newFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: oldFolder.path) {
                try fileManager.moveItem(at: oldFolder, to: newFolder)
            }
        } else if oldPath == nil, fileManager.fileExists(atPath: newFolder.path) {
            // Never adopt a folder that belongs to another record.
            let existing = newFolder.appendingPathComponent("document.json")
            if let data = try? Data(contentsOf: existing),
               let other = try? DocuDeskJSON.decoder.decode(DocumentRecord.self, from: data), other.id != document.id {
                throw WorkspaceError.conflictingFolder(newPath)
            }
        }

        do {
            try fileManager.createDirectory(at: newFolder, withIntermediateDirectories: true)
            let data = try DocuDeskJSON.encoder.encode(document)
            try data.write(to: newFolder.appendingPathComponent("document.json"), options: .atomic)
            // Hand back exactly what is on disk (JSON dates are whole seconds), so later
            // comparisons against the stored copy see no phantom changes.
            document = try DocuDeskJSON.decoder.decode(DocumentRecord.self, from: data)
        } catch let error as WorkspaceError {
            throw error
        } catch {
            throw WorkspaceError.notWritable(newFolder.path)
        }
        try database.transaction { try index(document, relativePath: newPath) }
        return document
    }

    private func index(_ document: DocumentRecord, relativePath: String) throws {
        let lastExport = document.exports.last
        try database.run("""
        INSERT INTO documents(id, kind, number, title, status, profile_id, customer_id, customer_name, issue_date, due_date, currency, total, total_minor, balance_minor, revision, rel_path, created_at, updated_at, last_export_path, last_exported_at, tags, pinned, archived, type_key, type_name)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, number = excluded.number, title = excluded.title, status = excluded.status,
            profile_id = excluded.profile_id, customer_id = excluded.customer_id, customer_name = excluded.customer_name,
            issue_date = excluded.issue_date, due_date = excluded.due_date, currency = excluded.currency, total = excluded.total,
            total_minor = excluded.total_minor, balance_minor = excluded.balance_minor, revision = excluded.revision,
            rel_path = excluded.rel_path, updated_at = excluded.updated_at, last_export_path = excluded.last_export_path,
            last_exported_at = excluded.last_exported_at, tags = excluded.tags, pinned = excluded.pinned, archived = excluded.archived,
            type_key = excluded.type_key, type_name = excluded.type_name
        """, [
            .text(document.id.uuidString), .text(document.kind.rawValue), .text(document.number), .text(document.displayTitle),
            .text(document.status.rawValue), .text(document.profileID.uuidString), .optional(document.customerID?.uuidString),
            .text(document.customer.name), .text(document.issueDate.iso), .optional(document.dueDate?.iso), .text(document.currency),
            .text(document.totals.grandTotal.plainString), .int(document.totals.grandTotal.minorUnits),
            .int(document.status == .paid || !document.showsPricing ? 0 : max(document.totals.balanceDue, 0).minorUnits), .int(Int64(document.revision)),
            .text(relativePath), .text(Self.timestamp.string(from: document.createdAt)), .text(Self.timestamp.string(from: document.updatedAt)),
            .optional(lastExport?.path), .optional(lastExport.map { Self.timestamp.string(from: $0.exportedAt) }),
            .text(Self.encodeTags(document.tags)), .int(document.pinned ? 1 : 0), .int(document.archived ? 1 : 0),
            .text(document.numberingKey), .text(document.typeName),
        ])
        try database.run("DELETE FROM documents_fts WHERE id = ?", [.text(document.id.uuidString)])
        try database.run("INSERT INTO documents_fts(id, number, title, customer, body) VALUES(?, ?, ?, ?, ?)", [
            .text(document.id.uuidString), .text(document.number), .text(document.displayTitle), .text(document.customer.name), .text(document.searchBody),
        ])
    }

    private func revisionsFolder(for document: DocumentRecord) throws -> URL {
        let folder = try workspace.resolve(folderPath(for: document)).appendingPathComponent("revisions", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeSnapshot(_ document: DocumentRecord, suffix: String) throws {
        let folder = try revisionsFolder(for: document)
        var name = "R\(document.revision)-\(suffix).json"
        var counter = 2
        while fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "R\(document.revision)-\(suffix)-\(counter).json"
            counter += 1
        }
        try DocuDeskJSON.encoder.encode(document).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    /// Freezes a draft: status becomes Issued and an immutable snapshot is kept in `revisions/`.
    @discardableResult
    public func issue(_ document: DocumentRecord) throws -> DocumentRecord {
        var document = document
        guard document.status == .draft else { return document }
        let missing = document.missingRequiredFields
        guard missing.isEmpty else { throw CustomTypeError.missingRequiredFields(missing) }
        if let customerID = document.customerID, let customer = try customer(id: customerID), customer.party != document.customer {
            // The document keeps what was typed; the customer record is not silently changed.
            _ = customer
        }
        document.status = .issued
        document.issuedAt = Date()
        let saved = try save(document)
        try writeSnapshot(saved, suffix: "issued")
        return saved
    }

    @discardableResult
    public func setStatus(_ status: DocumentStatus, for id: UUID) throws -> DocumentRecord {
        var document = try loadDocument(id: id)
        guard status != .draft || document.status == .draft else { throw WorkspaceError.documentLocked(document.number) }
        if document.status == .draft, status != .draft {
            document.status = status
            document.issuedAt = Date()
            let saved = try save(document)
            try writeSnapshot(saved, suffix: "issued")
            return saved
        }
        document.status = status
        return try save(document)
    }

    /// Re-opens an issued document as a new draft revision, keeping the previous one on disk.
    @discardableResult
    public func createRevision(of id: UUID) throws -> DocumentRecord {
        var document = try loadDocument(id: id)
        guard document.status.isContentLocked else { return document }
        try writeSnapshot(document, suffix: "superseded")
        document.revision += 1
        document.status = .draft
        document.issuedAt = nil
        return try write(document)
    }

    /// Copies a document into a new draft with a fresh number. The original is never touched.
    @discardableResult
    public func duplicate(_ id: UUID, as kind: DocumentKind? = nil, link: LinkKind = .duplicatedFrom) throws -> DocumentRecord {
        let original = try loadDocument(id: id)
        let targetKind = kind ?? original.kind
        let profile = try profile(id: original.profileID) ?? original.company
        let today = CalendarDate.today
        var copy = original
        copy.id = UUID()
        copy.kind = targetKind
        if targetKind == .custom, original.customType != nil {
            copy.number = try allocateNumber(key: original.numberingKey, defaultPrefix: original.defaultPrefix, kind: .custom, profileID: profile.id, year: today.year)
        } else {
            copy.customType = nil
            copy.customFields = [:]
            copy.number = try allocateNumber(kind: targetKind, profileID: profile.id, year: today.year)
        }
        copy.status = .draft
        copy.revision = 1
        copy.company = profile
        copy.issueDate = today
        copy.issuedAt = nil
        copy.exports = []
        copy.payments = []
        copy.pinned = false
        copy.archived = false
        copy.templateSnapshot = nil
        copy.links = [DocumentLink(kind: link, documentID: original.id, number: original.number)]
        copy.createdAt = Date()
        if let customerID = original.customerID, let customer = try customer(id: customerID) {
            copy.customer = customer.party
        }
        if targetKind != original.kind, CustomTemplate.id(from: original.templateID) == nil {
            let template = TemplateLibrary.template(id: original.templateID)
            copy.templateID = TemplateLibrary.defaultTemplate(for: targetKind, style: template?.style ?? profile.defaultTemplateStyle).id
            copy.templateVersion = 1
        }
        if !copy.usesBody { copy.body = RichTextBody() }
        if copy.usesLineItems, copy.items.isEmpty {
            copy.items = [LineItem(name: "", quantity: 1, unitPrice: 0, taxRate: profile.defaultTaxRate)]
        }
        copy.dueDate = copy.defaultDueDays(profile).map { today.adding(days: $0) }
        if targetKind == .invoice, original.kind.convertsToInvoice, copy.paymentDetails.isEmpty {
            copy.paymentDetails = profile.bankDetails
        }
        return try save(copy)
    }

    /// Creates an invoice from a quotation, estimate or proforma and links both ways; the source is marked accepted.
    @discardableResult
    public func convertToInvoice(_ id: UUID) throws -> DocumentRecord {
        var quotation = try loadDocument(id: id)
        let invoice = try duplicate(id, as: .invoice, link: .convertedFrom)
        quotation.links.append(DocumentLink(kind: .convertedTo, documentID: invoice.id, number: invoice.number))
        if quotation.status != .cancelled { quotation.status = .accepted }
        if quotation.issuedAt == nil { quotation.issuedAt = Date() }
        try write(quotation)
        return invoice
    }

    /// Drafts go to the macOS Trash (recoverable). Issued documents can't be deleted.
    public func deleteDraft(id: UUID, moveToTrash: Bool = true) throws {
        let document = try loadDocument(id: id)
        guard document.status == .draft, document.revision == 1 else { throw WorkspaceError.cannotDeleteIssued(document.number) }
        let folder = try documentFolder(for: id)
        if fileManager.fileExists(atPath: folder.path) {
            if moveToTrash {
                try fileManager.trashItem(at: folder, resultingItemURL: nil)
            } else {
                try fileManager.removeItem(at: folder)
            }
        }
        try database.transaction {
            try database.run("DELETE FROM documents WHERE id = ?", [.text(id.uuidString)])
            try database.run("DELETE FROM documents_fts WHERE id = ?", [.text(id.uuidString)])
        }
    }

    // MARK: Export

    public func pdfFileName(for document: DocumentRecord) -> String {
        let revision = document.revision > 1 ? "-R\(document.revision)" : ""
        return "\(document.number)\(revision).pdf"
    }

    /// Renders the PDF into the document's own folder and records the export.
    @discardableResult
    public func exportPDF(_ document: DocumentRecord) throws -> (document: DocumentRecord, url: URL) {
        let output = renderPDF(document)
        let folder = try workspace.resolve(folderPath(for: document))
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(pdfFileName(for: document))
        do {
            try output.data.write(to: url, options: .atomic)
        } catch {
            throw WorkspaceError.notWritable(url.path)
        }
        var updated = document
        let relative = workspace.relativePath(of: url) ?? url.lastPathComponent
        updated.exports.append(ExportRecord(path: relative, exportedAt: Date(), revision: document.revision))
        let saved = try write(updated)
        return (saved, url)
    }

    // MARK: Search

    public func search(_ query: DocumentQuery) throws -> [DocumentSummary] {
        var conditions: [String] = []
        var parameters: [SQLValue] = []
        var from = "documents d"

        let tokens = query.text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if !tokens.isEmpty {
            from = "documents d JOIN documents_fts f ON f.id = d.id"
            conditions.append("documents_fts MATCH ?")
            parameters.append(.text(tokens.map { "\"\($0)\"*" }.joined(separator: " ")))
        }
        if !query.kinds.isEmpty {
            conditions.append("d.kind IN (\(Array(repeating: "?", count: query.kinds.count).joined(separator: ",")))")
            parameters += query.kinds.map { .text($0.rawValue) }
        }
        if !query.statuses.isEmpty {
            var statusClauses: [String] = []
            let stored = query.statuses.subtracting([.overdue])
            if !stored.isEmpty {
                statusClauses.append("d.status IN (\(Array(repeating: "?", count: stored.count).joined(separator: ",")))")
                parameters += stored.map { .text($0.rawValue) }
            }
            if query.statuses.contains(.overdue) {
                statusClauses.append("(d.kind = 'invoice' AND d.status IN ('issued','sent','partiallyPaid','overdue') AND d.due_date < ? AND d.balance_minor > 0)")
                parameters.append(.text(CalendarDate.today.iso))
            }
            conditions.append("(" + statusClauses.joined(separator: " OR ") + ")")
        }
        if let customerID = query.customerID {
            conditions.append("d.customer_id = ?")
            parameters.append(.text(customerID.uuidString))
        }
        if let profileID = query.profileID {
            conditions.append("d.profile_id = ?")
            parameters.append(.text(profileID.uuidString))
        }
        if let customTypeID = query.customTypeID {
            conditions.append("d.type_key = ?")
            parameters.append(.text("custom.\(customTypeID.uuidString)"))
        }
        for tag in query.tags {
            conditions.append("d.tags LIKE ? ESCAPE '\\'")
            parameters.append(.text("%|" + Self.likeEscaped(tag.lowercased()) + "|%"))
        }
        if query.pinnedOnly { conditions.append("d.pinned = 1") }
        switch query.archive {
        case .active: conditions.append("d.archived = 0")
        case .archived: conditions.append("d.archived = 1")
        case .all: break
        }
        if let start = query.from {
            conditions.append("d.issue_date >= ?")
            parameters.append(.text(start.iso))
        }
        if let end = query.to {
            conditions.append("d.issue_date <= ?")
            parameters.append(.text(end.iso))
        }
        if let minAmount = query.minAmount {
            conditions.append("d.total_minor >= ?")
            parameters.append(.int(minAmount.minorUnits))
        }
        if let maxAmount = query.maxAmount {
            conditions.append("d.total_minor <= ?")
            parameters.append(.int(maxAmount.minorUnits))
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT d.* FROM \(from) \(whereClause) ORDER BY d.pinned DESC, d.issue_date DESC, d.number DESC LIMIT \(max(1, query.limit))"
        return try database.query(sql, parameters).compactMap(Self.summary(from:))
    }

    static func summary(from row: SQLRow) -> DocumentSummary? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
              let kind = row.string("kind").flatMap(DocumentKind.init(rawValue:)),
              let status = row.string("status").flatMap(DocumentStatus.init(rawValue:)),
              let issueDate = row.string("issue_date").flatMap(CalendarDate.init(iso:))
        else { return nil }
        return DocumentSummary(
            id: id,
            kind: kind,
            number: row.string("number") ?? "",
            title: row.string("title") ?? "",
            status: status,
            customerName: row.string("customer_name") ?? "",
            customerID: row.string("customer_id").flatMap(UUID.init(uuidString:)),
            issueDate: issueDate,
            dueDate: row.string("due_date").flatMap(CalendarDate.init(iso:)),
            currency: row.string("currency") ?? "INR",
            total: row.string("total").flatMap(Decimal.parse) ?? 0,
            balance: Decimal.fromMinorUnits(row.int("balance_minor") ?? 0),
            relativePath: row.string("rel_path") ?? "",
            updatedAt: row.string("updated_at").flatMap { timestamp.date(from: $0) } ?? Date(),
            lastExportPath: row.string("last_export_path"),
            lastExportedAt: row.string("last_exported_at").flatMap { timestamp.date(from: $0) },
            tags: decodeTags(row.string("tags") ?? ""),
            pinned: row.int("pinned") == 1,
            archived: row.int("archived") == 1,
            profileID: row.string("profile_id").flatMap(UUID.init(uuidString:)),
            typeName: row.string("type_name").flatMap { $0.isEmpty ? nil : $0 } ?? kind.displayName,
            typeKey: row.string("type_key").flatMap { $0.isEmpty ? nil : $0 } ?? kind.rawValue
        )
    }

    // MARK: Dashboard

    public func dashboardStats() throws -> DashboardStats {
        var stats = DashboardStats()
        for row in try database.query("SELECT kind, COUNT(*) AS n FROM documents GROUP BY kind") {
            if let kind = row.string("kind").flatMap(DocumentKind.init(rawValue:)) {
                stats.counts[kind] = Int(row.int("n") ?? 0)
            }
        }
        stats.drafts = Int(try database.query("SELECT COUNT(*) AS n FROM documents WHERE status = 'draft'").first?.int("n") ?? 0)

        func sums(_ column: String, _ condition: String, _ parameters: [SQLValue] = []) throws -> [CurrencyAmount] {
            try database.query("SELECT currency, SUM(\(column)) AS amount FROM documents WHERE kind = 'invoice' AND \(condition) GROUP BY currency ORDER BY currency", parameters)
                .map { CurrencyAmount(currency: $0.string("currency") ?? "", amount: Decimal.fromMinorUnits($0.int("amount") ?? 0)) }
                .filter { $0.amount != 0 }
        }
        let outstandingStatuses = "status IN ('issued','sent','partiallyPaid','overdue')"
        stats.invoiced = try sums("total_minor", "status NOT IN ('draft','cancelled')")
        stats.outstanding = try sums("balance_minor", outstandingStatuses)
        stats.overdue = try sums("balance_minor", "\(outstandingStatuses) AND due_date < ? AND balance_minor > 0", [.text(CalendarDate.today.iso)])
        stats.paid = try sums("total_minor", "status = 'paid'")
        stats.overdueCount = Int(try database.query(
            "SELECT COUNT(*) AS n FROM documents WHERE kind = 'invoice' AND \(outstandingStatuses) AND due_date < ? AND balance_minor > 0",
            [.text(CalendarDate.today.iso)]
        ).first?.int("n") ?? 0)
        stats.recent = try database.query("SELECT * FROM documents ORDER BY updated_at DESC LIMIT 8").compactMap(Self.summary(from:))
        stats.recentExports = try database.query("SELECT * FROM documents WHERE last_exported_at IS NOT NULL ORDER BY last_exported_at DESC LIMIT 6").compactMap(Self.summary(from:))
        return stats
    }

    // MARK: Index maintenance

    /// Rebuilds the document index from the JSON files on disk. Unreadable files are reported, not deleted.
    public func rebuildIndex() throws -> RebuildReport {
        var report = RebuildReport()
        var records: [(DocumentRecord, String)] = []
        if let enumerator = fileManager.enumerator(at: workspace.documentsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.lastPathComponent == "document.json" {
                guard url.deletingLastPathComponent().lastPathComponent != "revisions" else { continue }
                let relative = workspace.relativePath(of: url.deletingLastPathComponent()) ?? url.path
                do {
                    let record = try DocuDeskJSON.decoder.decode(DocumentRecord.self, from: Data(contentsOf: url))
                    records.append((record, relative))
                } catch {
                    report.damaged.append((relative, "Unreadable document.json: \(error.localizedDescription)"))
                }
            }
        }
        try database.transaction {
            try database.execute("DELETE FROM documents; DELETE FROM documents_fts;")
            var seen = Set<UUID>()
            for (record, relative) in records.sorted(by: { $0.1 < $1.1 }) {
                guard seen.insert(record.id).inserted else {
                    report.damaged.append((relative, "Duplicate document ID \(record.id.uuidString)"))
                    continue
                }
                do {
                    try index(record, relativePath: relative)
                    report.indexed += 1
                } catch let error as SQLiteError where error.isConstraintViolation {
                    report.damaged.append((relative, "Duplicate number \(record.number)"))
                }
            }
        }
        return report
    }

    /// Index entries whose files have gone missing, e.g. after manual edits in Finder.
    public func missingDocumentFiles() throws -> [DocumentSummary] {
        try search(DocumentQuery()).filter { summary in
            guard let folder = try? workspace.resolve(summary.relativePath) else { return true }
            return !fileManager.fileExists(atPath: folder.appendingPathComponent("document.json").path)
        }
    }
}
