import Foundation

public struct RevisionSnapshot: Identifiable, Hashable, Sendable {
    /// File name inside the document's `revisions/` folder.
    public let id: String
    public let revision: Int
    public let label: String
    public let savedAt: Date
    public let document: DocumentRecord
}

extension WorkspaceStore {
    /// Earlier versions kept in the document's `revisions/` folder, newest first.
    public func revisions(of id: UUID) throws -> [RevisionSnapshot] {
        let folder = try documentFolder(for: id).appendingPathComponent("revisions", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name -> RevisionSnapshot? in
            let url = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let document = try? DocuDeskJSON.decoder.decode(DocumentRecord.self, from: data) else { return nil }
            let label: String
            if name.contains("-issued") {
                label = "Issued"
            } else if name.contains("-superseded") {
                label = "Replaced by a revision"
            } else if name.contains("-restore") {
                label = "Before restore"
            } else {
                label = "Saved copy"
            }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? document.updatedAt
            return RevisionSnapshot(id: name, revision: document.revision, label: label, savedAt: modified, document: document)
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    /// Brings back the content of an earlier version. An issued document first becomes a new
    /// revision, and the current content is also kept as a snapshot, so nothing is lost.
    @discardableResult
    public func restoreRevision(_ snapshot: RevisionSnapshot, into id: UUID) throws -> DocumentRecord {
        var current = try loadDocument(id: id)
        if current.status.isContentLocked {
            current = try createRevision(of: id)
        } else {
            try keepSnapshot(current, suffix: "restore")
        }
        var restored = snapshot.document
        restored.id = current.id
        restored.number = current.number
        restored.status = .draft
        restored.revision = current.revision
        restored.issuedAt = nil
        restored.templateSnapshot = nil
        restored.links = current.links
        restored.exports = current.exports
        restored.payments = current.payments
        restored.tags = current.tags
        restored.pinned = current.pinned
        restored.archived = current.archived
        restored.createdAt = current.createdAt
        return try save(restored)
    }

    private func keepSnapshot(_ document: DocumentRecord, suffix: String) throws {
        let folder = try documentFolder(for: document.id).appendingPathComponent("revisions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let url = Self.uniqueURL(in: folder, name: "R\(document.revision)-\(suffix)-\(stamp).json")
        try DocuDeskJSON.encoder.encode(document).write(to: url, options: .atomic)
    }
}
