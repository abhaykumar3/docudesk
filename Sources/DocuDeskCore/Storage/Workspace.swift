import Foundation

public struct WorkspaceManifest: Codable, Hashable, Sendable {
    public var id: UUID
    public var formatVersion: Int
    public var createdAt: Date
    public var createdBy: String
}

public enum WorkspaceError: LocalizedError, Equatable {
    case folderMissing(String)
    case notAWorkspace(String)
    case databaseMissing(String)
    case unsupportedFormat(Int)
    case notWritable(String)
    case duplicateNumber(String)
    case invalidNumber(String)
    case documentLocked(String)
    case recordNotFound
    case unsafePath(String)
    case cannotDeleteIssued(String)
    case conflictingFolder(String)
    case invalidImage

    public var errorDescription: String? {
        switch self {
        case let .folderMissing(path):
            "The DocuDesk folder at “\(path)” can’t be found. If it’s on an external drive, connect the drive and try again."
        case let .notAWorkspace(path):
            "“\(path)” isn’t a DocuDesk workspace (workspace.json is missing)."
        case let .databaseMissing(path):
            "The database in “\(path)” is missing. Your document files are still there; you can rebuild the index from them or restore a backup."
        case let .unsupportedFormat(version):
            "This workspace was created by a newer version of DocuDesk (format \(version)). Update the app to open it."
        case let .notWritable(path):
            "DocuDesk can’t write to “\(path)”. Check the folder’s permissions and free disk space."
        case let .duplicateNumber(number):
            "The number \(number) is already used by another document of this type."
        case let .invalidNumber(number):
            "“\(number)” can’t be used as a document number. Avoid slashes, colons and leading dots."
        case let .documentLocked(number):
            "\(number) has been issued, so its content can’t change. Create a revision to make corrections."
        case .recordNotFound:
            "The record could not be found. It may have been moved or deleted outside DocuDesk."
        case let .unsafePath(path):
            "Refused to access “\(path)” because it is outside the workspace."
        case let .cannotDeleteIssued(number):
            "\(number) has been issued and can’t be deleted. Mark it as cancelled instead."
        case let .conflictingFolder(path):
            "A different document already occupies “\(path)”. Nothing was overwritten."
        case .invalidImage:
            "That file isn’t a supported image."
        }
    }
}

public struct Workspace: Sendable {
    public static let formatVersion = 1
    public static let manifestName = "workspace.json"

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public var manifestURL: URL { root.appendingPathComponent(Self.manifestName) }
    public var databaseFolder: URL { root.appendingPathComponent("Database", isDirectory: true) }
    public var databaseURL: URL { databaseFolder.appendingPathComponent("docudesk.sqlite") }
    public var documentsURL: URL { root.appendingPathComponent("Documents", isDirectory: true) }
    public var templatesURL: URL { root.appendingPathComponent("Templates", isDirectory: true) }
    public var assetsURL: URL { root.appendingPathComponent("Assets", isDirectory: true) }
    public var backupsURL: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    public var exportsURL: URL { root.appendingPathComponent("Exports", isDirectory: true) }

    public var standardFolders: [URL] {
        [databaseFolder, documentsURL, templatesURL, assetsURL, backupsURL, exportsURL]
    }

    public static var defaultLocation: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DocuDesk", isDirectory: true)
    }

    public static func isWorkspace(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(manifestName).path)
    }

    /// Resolves a workspace-relative path, refusing anything that escapes the root.
    public func resolve(_ relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else {
            throw WorkspaceError.unsafePath(relativePath)
        }
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw WorkspaceError.unsafePath(relativePath)
        }
        return url
    }

    public func relativePath(of url: URL) -> String? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root.path + "/") else { return nil }
        return String(path.dropFirst(root.path.count + 1))
    }
}

public enum DocuDeskJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
