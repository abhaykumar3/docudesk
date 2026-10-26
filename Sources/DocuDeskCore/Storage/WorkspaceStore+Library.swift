import AppKit
import Foundation

public struct TemplateFile: Codable, Sendable {
    public static let fileExtension = "docudesktemplate"
    public var format = "docudesk-template"
    public var formatVersion = 1
    public var template: CustomTemplate
}

public enum LibraryError: LocalizedError {
    case invalidTemplateFile
    case cannotDeletePrimaryProfile
    case profileHasDocuments(Int)
    case lastProfile

    public var errorDescription: String? {
        switch self {
        case .invalidTemplateFile: "That file isn’t a valid DocuDesk template."
        case .cannotDeletePrimaryProfile: "The workspace’s first company profile can’t be deleted."
        case let .profileHasDocuments(count): "This profile has \(count) document(s). Profiles with documents can’t be deleted."
        case .lastProfile: "A workspace needs at least one company profile."
        }
    }
}

// MARK: - Company profiles

extension WorkspaceStore {
    /// The workspace's first profile. Its documents live directly in `Documents/`; others get a
    /// subfolder. Recorded once, because profile timestamps alone can tie.
    public func primaryProfileID() -> UUID? {
        if let raw = setting(.primaryProfileID), let id = UUID(uuidString: raw) { return id }
        guard let first = (try? profiles())?.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
        try? setSetting(.primaryProfileID, first.id.uuidString)
        return first.id
    }

    func profileFolderName(for id: UUID) -> String? {
        guard id != primaryProfileID(), let profile = try? profile(id: id) else { return nil }
        return profile.folderName.isEmpty ? Self.folderSlug(profile.name, id: profile.id) : profile.folderName
    }

    static func folderSlug(_ name: String, id: UUID) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -&()."))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let base = cleaned.isEmpty ? "Company" : String(cleaned.prefix(40))
        return "\(base) (\(id.uuidString.prefix(4)))"
    }

    /// Adds a company profile with its own numbering, defaults and document folder.
    @discardableResult
    public func createProfile(name: String, copyingDefaultsFrom source: CompanyProfile? = nil) throws -> CompanyProfile {
        var profile = CompanyProfile(name: name.trimmingCharacters(in: .whitespaces))
        if let source {
            profile.defaultCurrency = source.defaultCurrency
            profile.defaultTaxRate = source.defaultTaxRate
            profile.defaultTaxSplit = source.defaultTaxSplit
            profile.defaultTaxMode = source.defaultTaxMode
            profile.defaultPaymentTermsDays = source.defaultPaymentTermsDays
            profile.defaultQuoteValidityDays = source.defaultQuoteValidityDays
            profile.defaultTemplateStyle = source.defaultTemplateStyle
            profile.defaultPageSize = source.defaultPageSize
            profile.taxIDLabel = source.taxIDLabel
        }
        profile.folderName = Self.folderSlug(profile.name, id: profile.id)
        try saveProfile(profile)
        return profile
    }

    public func setActiveProfile(_ id: UUID) throws {
        try setSetting(.defaultProfileID, id.uuidString)
    }

    public func deleteProfile(_ id: UUID) throws {
        let all = try profiles()
        guard all.count > 1 else { throw LibraryError.lastProfile }
        guard id != primaryProfileID() else { throw LibraryError.cannotDeletePrimaryProfile }
        var query = DocumentQuery()
        query.profileID = id
        query.archive = .all
        let count = try search(query).count
        guard count == 0 else { throw LibraryError.profileHasDocuments(count) }
        try database.run("DELETE FROM profiles WHERE id = ?", [.text(id.uuidString)])
        if setting(.defaultProfileID) == id.uuidString, let fallback = primaryProfileID() {
            try setActiveProfile(fallback)
        }
    }
}

// MARK: - Custom templates

extension WorkspaceStore {
    public func customTemplates() throws -> [CustomTemplate] {
        try database.query("SELECT json FROM custom_templates ORDER BY name COLLATE NOCASE").compactMap { row in
            row.string("json").flatMap { $0.data(using: .utf8) }.flatMap { try? DocuDeskJSON.decoder.decode(CustomTemplate.self, from: $0) }
        }
    }

    public func customTemplate(id: UUID) throws -> CustomTemplate? {
        try database.query("SELECT json FROM custom_templates WHERE id = ?", [.text(id.uuidString)]).first
            .flatMap { $0.string("json")?.data(using: .utf8) }
            .flatMap { try? DocuDeskJSON.decoder.decode(CustomTemplate.self, from: $0) }
    }

    /// Saves a custom template. A changed theme becomes a new version; the old one is kept.
    @discardableResult
    public func saveCustomTemplate(_ template: CustomTemplate) throws -> CustomTemplate {
        var template = template
        template.name = template.name.trimmingCharacters(in: .whitespaces)
        if template.name.isEmpty { template.name = "Untitled template" }
        if let existing = try customTemplate(id: template.id), existing.theme != template.theme {
            template.history = existing.history + [TemplateVersion(version: existing.version, theme: existing.theme, savedAt: existing.updatedAt)]
            template.version = existing.version + 1
        }
        template.updatedAt = Date()
        let json = String(decoding: try DocuDeskJSON.encoder.encode(template), as: UTF8.self)
        try database.run(
            "INSERT INTO custom_templates(id, name, json, updated_at) VALUES(?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, json = excluded.json, updated_at = excluded.updated_at",
            [.text(template.id.uuidString), .text(template.name), .text(json), .text(Self.timestamp.string(from: template.updatedAt))]
        )
        return template
    }

    /// Issued documents keep a snapshot; drafts using a deleted template fall back to a built-in style.
    public func deleteCustomTemplate(id: UUID) throws {
        try database.run("DELETE FROM custom_templates WHERE id = ?", [.text(id.uuidString)])
    }

    public func templateDefinition(id: String?, kind: DocumentKind) throws -> TemplateDefinition? {
        guard let id else { return nil }
        if let customID = CustomTemplate.id(from: id) {
            return try customTemplate(id: customID)?.definition(for: kind)
        }
        return TemplateLibrary.template(id: id).map { $0.kind == kind ? $0 : TemplateLibrary.defaultTemplate(for: kind, style: $0.style) }
    }

    /// The theme a document renders with: its issued snapshot, its custom template (at the right
    /// version), or a built-in template.
    public func theme(for document: DocumentRecord) -> TemplateTheme {
        if document.status.isContentLocked, let snapshot = document.templateSnapshot { return snapshot }
        if let customID = CustomTemplate.id(from: document.templateID), let custom = try? customTemplate(id: customID) {
            return document.status.isContentLocked ? custom.theme(forVersion: document.templateVersion) : custom.theme
        }
        return TemplateLibrary.resolve(id: document.templateID, kind: document.kind).template.theme
    }

    public func templateIsMissing(for document: DocumentRecord) -> Bool {
        if document.status.isContentLocked, document.templateSnapshot != nil { return false }
        if let customID = CustomTemplate.id(from: document.templateID) {
            return (try? customTemplate(id: customID)) == nil
        }
        return TemplateLibrary.template(id: document.templateID) == nil
    }

    public func templateName(for document: DocumentRecord) -> String {
        if let customID = CustomTemplate.id(from: document.templateID), let custom = try? customTemplate(id: customID) {
            return custom.name
        }
        return TemplateLibrary.resolve(id: document.templateID, kind: document.kind).template.name
    }

    /// Renders with the document's logo and resolved theme.
    public func renderPDF(_ document: DocumentRecord) -> DocumentRenderer.Output {
        let output = DocumentRenderer.render(document, logo: image(at: document.company.logoPath), theme: theme(for: document))
        return DocumentRenderer.Output(data: output.data, pageCount: output.pageCount, usedFallbackTemplate: templateIsMissing(for: document))
    }

    public func exportTemplate(_ template: CustomTemplate, to url: URL) throws {
        try DocuDeskJSON.encoder.encode(TemplateFile(template: template)).write(to: url, options: .atomic)
    }

    /// Imports a template file as a new template (fresh ID, version history dropped).
    @discardableResult
    public func importTemplate(from url: URL) throws -> CustomTemplate {
        guard let data = try? Data(contentsOf: url), data.count < 1_000_000,
              let file = try? DocuDeskJSON.decoder.decode(TemplateFile.self, from: data),
              file.format == "docudesk-template", file.formatVersion <= 1
        else { throw LibraryError.invalidTemplateFile }
        var template = CustomTemplate(name: String(file.template.name.prefix(80)), baseStyle: file.template.baseStyle, theme: file.template.theme)
        template.theme.footerNote = String(template.theme.footerNote.prefix(200))
        return try saveCustomTemplate(template)
    }
}

// MARK: - Clauses

extension WorkspaceStore {
    /// Reusable clauses; built-ins are added the first time the library is opened.
    public func clauses() throws -> [Clause] {
        if setting(.clausesSeeded) == nil {
            try database.transaction {
                for clause in ClauseLibrary.builtIn { try saveClause(clause) }
                try setSetting(.clausesSeeded, "true")
            }
        }
        return try database.query("SELECT json FROM clauses ORDER BY category COLLATE NOCASE, title COLLATE NOCASE").compactMap { row in
            row.string("json").flatMap { $0.data(using: .utf8) }.flatMap { try? DocuDeskJSON.decoder.decode(Clause.self, from: $0) }
        }
    }

    public func saveClause(_ clause: Clause) throws {
        var clause = clause
        clause.updatedAt = Date()
        let json = String(decoding: try DocuDeskJSON.encoder.encode(clause), as: UTF8.self)
        try database.run(
            "INSERT INTO clauses(id, title, category, json, updated_at) VALUES(?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title = excluded.title, category = excluded.category, json = excluded.json, updated_at = excluded.updated_at",
            [.text(clause.id.uuidString), .text(clause.title), .text(clause.category), .text(json), .text(Self.timestamp.string(from: clause.updatedAt))]
        )
    }

    public func deleteClause(id: UUID) throws {
        try database.run("DELETE FROM clauses WHERE id = ?", [.text(id.uuidString)])
    }
}
