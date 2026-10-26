import CryptoKit
import Foundation

public struct BackupManifest: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var path: String
        public var size: Int64
        public var sha256: String
    }

    public var formatVersion: Int
    public var workspaceFormatVersion: Int
    public var databaseSchemaVersion: Int
    public var workspaceID: UUID
    public var createdAt: Date
    public var documentCount: Int
    public var automatic: Bool
    public var files: [Entry]
}

public struct BackupRecord: Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let createdAt: Date
    public let verified: Bool
    public let automatic: Bool
    public let size: Int64
    public let encrypted: Bool
}

public enum BackupError: LocalizedError {
    case toolFailed(String)
    case missingManifest
    case incompatible(Int)
    case checksumMismatch(String)
    case missingFile(String)
    case unexpectedFile(String)
    case destinationUnavailable(String)
    case passwordRequired

    public var errorDescription: String? {
        switch self {
        case let .toolFailed(message): "The backup archive could not be processed: \(message)"
        case .missingManifest: "This file isn’t a DocuDesk backup (manifest.json is missing)."
        case let .incompatible(version): "This backup was made by a newer version of DocuDesk (format \(version))."
        case let .checksumMismatch(path): "The backup is damaged: “\(path)” doesn’t match its checksum."
        case let .missingFile(path): "The backup is incomplete: “\(path)” is missing."
        case let .unexpectedFile(path): "The backup contains an unexpected file “\(path)” and was rejected."
        case let .destinationUnavailable(path): "The backup destination “\(path)” isn’t available. Connect the drive or choose another folder."
        case .passwordRequired: "This backup is encrypted. Enter its password to continue."
        }
    }
}

public enum BackupService {
    public static let fileExtension = "docudeskbackup"
    public static let formatVersion = 1
    private static let contentFolders = ["Documents", "Templates", "Assets"]

    // MARK: Create

    /// Writes a verified backup package into `directory` and records it in the database.
    @discardableResult
    public static func createBackup(of store: WorkspaceStore, in directory: URL, automatic: Bool = false, password: String? = nil) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            // Only the default in-workspace folder is created on demand; external destinations must exist.
            guard directory.standardizedFileURL == store.workspace.backupsURL.standardizedFileURL else {
                throw BackupError.destinationUnavailable(directory.path)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else if !isDirectory.boolValue {
            throw BackupError.destinationUnavailable(directory.path)
        }

        let staging = fileManager.temporaryDirectory.appendingPathComponent("DocuDesk-Backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging.appendingPathComponent("Database"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try store.database.snapshot(to: staging.appendingPathComponent("Database/docudesk.sqlite"))
        try fileManager.copyItem(at: store.workspace.manifestURL, to: staging.appendingPathComponent(Workspace.manifestName))
        for folder in contentFolders {
            let source = store.workspace.root.appendingPathComponent(folder)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: staging.appendingPathComponent(folder))
            }
        }

        let documentCount = (try? store.search(DocumentQuery()).count) ?? 0
        let manifest = BackupManifest(
            formatVersion: formatVersion,
            workspaceFormatVersion: Workspace.formatVersion,
            databaseSchemaVersion: WorkspaceStore.schemaVersion,
            workspaceID: store.manifest.id,
            createdAt: Date(),
            documentCount: documentCount,
            automatic: automatic,
            files: try entries(in: staging)
        )
        try DocuDeskJSON.encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)

        let stamp = stampFormatter.string(from: manifest.createdAt)
        let final = uniqueURL(in: directory, base: "DocuDesk Backup \(stamp)\(automatic ? " (auto)" : "")")
        let partial = final.appendingPathExtension("partial")
        try runDitto(["-c", "-k", "--sequesterRsrc", staging.path, partial.path])
        if let password, !password.isEmpty {
            let sealed = final.appendingPathExtension("sealing")
            defer { try? fileManager.removeItem(at: partial) }
            try BackupCrypto.encrypt(partial, to: sealed, password: password)
            try fileManager.moveItem(at: sealed, to: final)
        } else {
            try fileManager.moveItem(at: partial, to: final)
        }

        // A backup only counts once it has been read back and checked.
        let verifiedRoot = try verify(final, password: password).extractedRoot
        try? fileManager.removeItem(at: verifiedRoot.deletingLastPathComponent())

        let size = (try? fileManager.attributesOfItem(atPath: final.path)[.size] as? Int64) ?? 0
        try store.database.run(
            "INSERT INTO backups(id, path, created_at, verified, automatic, size, encrypted) VALUES(?, ?, ?, 1, ?, ?, ?)",
            [.text(UUID().uuidString), .text(final.path), .text(ISO8601DateFormatter().string(from: manifest.createdAt)), .int(automatic ? 1 : 0), .int(size),
             .int(password?.isEmpty == false ? 1 : 0)]
        )
        return final
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .posix
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static func uniqueURL(in directory: URL, base: String) -> URL {
        var url = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return url
    }

    private static func entries(in root: URL) throws -> [BackupManifest.Entry] {
        var result: [BackupManifest.Entry] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            guard relative != "manifest.json" else { continue }
            result.append(BackupManifest.Entry(path: relative, size: Int64(values.fileSize ?? 0), sha256: try sha256(of: url)))
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw BackupError.toolFailed(message.isEmpty ? "ditto exited with status \(process.terminationStatus)" : message)
        }
    }

    // MARK: Verify

    /// Extracts the package to a temporary folder and checks every file against the manifest.
    /// The caller owns `extractedRoot`'s parent folder and should delete it when done.
    public static func verify(_ url: URL, password: String? = nil) throws -> (manifest: BackupManifest, extractedRoot: URL) {
        let fileManager = FileManager.default
        let container = fileManager.temporaryDirectory.appendingPathComponent("DocuDesk-Verify-\(UUID().uuidString)", isDirectory: true)
        let root = container.appendingPathComponent("content", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            var archive = url
            if BackupCrypto.isEncrypted(url) {
                guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
                archive = container.appendingPathComponent("decrypted.zip")
                try BackupCrypto.decrypt(url, to: archive, password: password)
            }
            try runDitto(["-x", "-k", archive.path, root.path])
            guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
                  let manifest = try? DocuDeskJSON.decoder.decode(BackupManifest.self, from: data)
            else { throw BackupError.missingManifest }
            guard manifest.formatVersion <= formatVersion, manifest.workspaceFormatVersion <= Workspace.formatVersion,
                  manifest.databaseSchemaVersion <= WorkspaceStore.schemaVersion
            else { throw BackupError.incompatible(manifest.formatVersion) }

            let sandbox = Workspace(root: root)
            var expected = Set<String>()
            for entry in manifest.files {
                let fileURL = try sandbox.resolve(entry.path)
                guard fileManager.fileExists(atPath: fileURL.path) else { throw BackupError.missingFile(entry.path) }
                guard try sha256(of: fileURL) == entry.sha256 else { throw BackupError.checksumMismatch(entry.path) }
                expected.insert(entry.path)
            }
            for entry in try entries(in: root) where !expected.contains(entry.path) {
                throw BackupError.unexpectedFile(entry.path)
            }
            guard expected.contains("Database/docudesk.sqlite"), expected.contains(Workspace.manifestName) else {
                throw BackupError.missingFile("Database/docudesk.sqlite")
            }
            return (manifest, root)
        } catch {
            try? fileManager.removeItem(at: container)
            throw error
        }
    }

    // MARK: Restore

    /// Replaces the workspace content with a verified backup. The current content is moved, not
    /// deleted, into `Backups/Before Restore <date>/`. The store for `root` must be closed first.
    @discardableResult
    public static func restore(_ url: URL, intoWorkspaceAt root: URL, password: String? = nil) throws -> URL {
        let fileManager = FileManager.default
        let workspace = Workspace(root: root)
        let (_, extracted) = try verify(url, password: password)
        defer { try? fileManager.removeItem(at: extracted.deletingLastPathComponent()) }

        let safety = workspace.backupsURL.appendingPathComponent("Before Restore \(stampFormatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: safety, withIntermediateDirectories: true)
        let items = ["Database"] + contentFolders
        var moved: [String] = []
        do {
            for item in items {
                let current = root.appendingPathComponent(item)
                if fileManager.fileExists(atPath: current.path) {
                    try fileManager.moveItem(at: current, to: safety.appendingPathComponent(item))
                    moved.append(item)
                }
            }
            for item in items {
                let source = extracted.appendingPathComponent(item)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: root.appendingPathComponent(item))
                } else {
                    try fileManager.createDirectory(at: root.appendingPathComponent(item), withIntermediateDirectories: true)
                }
            }
        } catch {
            // Put the previous content back so a failed restore never leaves a half-empty workspace.
            for item in items where moved.contains(item) {
                let target = root.appendingPathComponent(item)
                try? fileManager.removeItem(at: target)
                try? fileManager.moveItem(at: safety.appendingPathComponent(item), to: target)
            }
            throw error
        }
        return safety
    }

    // MARK: History and retention

    public static func history(of store: WorkspaceStore) -> [BackupRecord] {
        let formatter = ISO8601DateFormatter()
        let rows = (try? store.database.query("SELECT * FROM backups ORDER BY created_at DESC")) ?? []
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let path = row.string("path"),
                  let created = row.string("created_at").flatMap(formatter.date(from:)) else { return nil }
            return BackupRecord(id: id, path: path, createdAt: created, verified: row.int("verified") == 1,
                                automatic: row.int("automatic") == 1, size: row.int("size") ?? 0, encrypted: row.int("encrypted") == 1)
        }
    }

    public static func lastBackupDate(of store: WorkspaceStore) -> Date? {
        history(of: store).first?.createdAt
    }

    /// Deletes the oldest automatic backups beyond `keep`. Manual backups are never removed.
    public static func applyRetention(to store: WorkspaceStore, keep: Int) {
        let automatic = history(of: store).filter(\.automatic)
        guard keep > 0, automatic.count > keep else { return }
        for record in automatic.dropFirst(keep) {
            try? FileManager.default.removeItem(atPath: record.path)
            try? store.database.run("DELETE FROM backups WHERE id = ?", [.text(record.id.uuidString)])
        }
    }
}
