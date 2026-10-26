import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Password-based encryption for backup packages.
///
/// Format: `DDENC1` · version (1 byte) · salt (16) · PBKDF2 iterations (UInt32 BE) · then chunks of
/// `length (UInt32 BE) · AES-GCM combined box`. Each chunk authenticates the header, its index and
/// whether it is the last chunk, so reordering, truncation and tampering are all detected.
public enum BackupCrypto {
    static let magic = Data("DDENC1".utf8)
    static let version: UInt8 = 1
    static let iterations: UInt32 = 310_000
    static let chunkSize = 1 << 20

    public enum CryptoError: LocalizedError, Equatable {
        case wrongPassword
        case damaged
        case unsupported
        case keyDerivationFailed

        public var errorDescription: String? {
            switch self {
            case .wrongPassword: "The password is incorrect, or the backup has been altered."
            case .damaged: "The encrypted backup is incomplete or damaged."
            case .unsupported: "This encrypted backup was made by a newer version of DocuDesk."
            case .keyDerivationFailed: "The encryption key couldn’t be created."
            }
        }
    }

    public static func isEncrypted(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: magic.count)) == magic
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        var key = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &key, key.count)
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: key)
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func readUInt32(_ data: Data) -> UInt32 {
        data.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    private static func associatedData(header: Data, index: UInt32, final: Bool) -> Data {
        header + bigEndian(index) + Data([final ? 1 : 0])
    }

    public static func encrypt(_ source: URL, to destination: URL, password: String) throws {
        var salt = Data(count: 16)
        let saltStatus = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard saltStatus == errSecSuccess else { throw CryptoError.keyDerivationFailed }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let header = magic + Data([version]) + salt + bigEndian(iterations)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try output.write(contentsOf: header)

        var index: UInt32 = 0
        var chunk = try input.read(upToCount: chunkSize) ?? Data()
        repeat {
            let next = try input.read(upToCount: chunkSize) ?? Data()
            let final = next.isEmpty
            let sealed = try AES.GCM.seal(chunk, using: key, authenticating: associatedData(header: header, index: index, final: final))
            guard let combined = sealed.combined else { throw CryptoError.damaged }
            try output.write(contentsOf: bigEndian(UInt32(combined.count)) + combined)
            chunk = next
            index += 1
            if final { break }
        } while true
    }

    public static func decrypt(_ source: URL, to destination: URL, password: String) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard let prefix = try input.read(upToCount: magic.count + 1 + 16 + 4), prefix.count == magic.count + 21,
              prefix.prefix(magic.count) == magic else { throw CryptoError.damaged }
        guard prefix[magic.count] <= version else { throw CryptoError.unsupported }
        let salt = prefix.subdata(in: magic.count + 1 ..< magic.count + 17)
        let rounds = readUInt32(prefix.subdata(in: magic.count + 17 ..< magic.count + 21))
        guard rounds >= 100_000, rounds <= 10_000_000 else { throw CryptoError.damaged }
        let key = try deriveKey(password: password, salt: salt, iterations: rounds)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var index: UInt32 = 0
        var sawFinal = false
        while let lengthData = try input.read(upToCount: 4), !lengthData.isEmpty {
            guard !sawFinal, lengthData.count == 4 else { throw CryptoError.damaged }
            let length = Int(readUInt32(lengthData))
            guard length > 28, length <= chunkSize + 64, let combined = try input.read(upToCount: length), combined.count == length else {
                throw CryptoError.damaged
            }
            let box = try AES.GCM.SealedBox(combined: combined)
            let peek = try input.read(upToCount: 1) ?? Data()
            let final = peek.isEmpty
            if !final { try input.seek(toOffset: try input.offset() - 1) }
            let plain: Data
            do {
                plain = try AES.GCM.open(box, using: key, authenticating: associatedData(header: prefix, index: index, final: final))
            } catch {
                throw index == 0 ? CryptoError.wrongPassword : CryptoError.damaged
            }
            try output.write(contentsOf: plain)
            sawFinal = final
            index += 1
        }
        guard sawFinal else { throw CryptoError.damaged }
    }
}

/// Stores the backup password in the login Keychain so automatic backups can be encrypted.
public enum BackupKeychain {
    static let service = "DocuDesk Backup Encryption"

    public static func save(_ password: String, workspaceID: UUID) throws {
        delete(workspaceID: workspaceID)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: workspaceID.uuidString,
            kSecValueData: Data(password.utf8),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "The password couldn’t be saved to the Keychain (\(status))."])
        }
    }

    public static func load(workspaceID: UUID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: workspaceID.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(workspaceID: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: workspaceID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
