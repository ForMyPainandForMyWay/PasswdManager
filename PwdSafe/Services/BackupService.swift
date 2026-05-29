import Foundation
import CryptoKit
import Security

struct BackupRecord: Codable, Sendable {
    var version: Int
    var salt: Data?
    var encryptedVaultKey: Data?
    var encryptedBackupKey: Data?
    var encryptedBackupKeyLocal: Data?
    var createdAt: Date
    var appVersion: String
    var items: [BackupItem]
    var groups: [BackupGroup]
    var tags: [BackupTag]
}

struct BackupItem: Codable, Sendable {
    var id: UUID; var title: String; var website: String?; var username: String?
    var email: String?; var phone: String?; var notePreview: String?
    var isFavorite: Bool; var isDeleted: Bool; var deletedAt: Date?
    var createdAt: Date; var updatedAt: Date; var lastUsedAt: Date?; var groupID: UUID?; var tagIDs: [UUID]
    var encryptedSecret: EncryptedSecret
}

struct BackupGroup: Codable, Sendable {
    var id: UUID; var name: String; var colorHex: String?; var colorHexes: [String]?
    var sortOrder: Int; var createdAt: Date; var updatedAt: Date
}

struct BackupTag: Codable, Sendable {
    var id: UUID; var name: String; var colorHex: String?; var colorHexes: [String]?
    var createdAt: Date; var updatedAt: Date
}

enum BackupError: Error {
    case invalidFormat
    case versionMismatch
    case writeFailed
    case readFailed
    case missingVaultKey
    case wrongPassword
    case legacyVersionUnsupported
    case needsPassword
}

struct BackupService: Sendable {
    static let currentVersion = 3
    static let fileExtension = "pwd"
    static let utiType = "com.pwdsafe.pwd"

    // MARK: - Export

    static func exportBackup(
        items: [VaultItem],
        groups: [VaultGroup],
        tags: [VaultTag],
        keychainStore: KeychainStore
    ) throws -> BackupRecord {
        var backupItems: [BackupItem] = []
        for item in items {
            let encryptedData = try keychainStore.loadSecret(for: item.secretRef)
            let encrypted = try JSONDecoder().decode(EncryptedSecret.self, from: encryptedData)
            backupItems.append(BackupItem(
                id: item.id, title: item.title, website: item.website,
                username: item.username, email: item.email, phone: item.phone,
                notePreview: item.notePreview, isFavorite: item.isFavorite,
                isDeleted: item.isDeleted, deletedAt: item.deletedAt,
                createdAt: item.createdAt, updatedAt: item.updatedAt,
                lastUsedAt: item.lastUsedAt,
                groupID: item.group?.id, tagIDs: item.tags.map(\.id),
                encryptedSecret: encrypted
            ))
        }
        let backupGroups = groups.map { g in
            BackupGroup(id: g.id, name: g.name, colorHex: g.colorHex,
                        colorHexes: g.colorHexes, sortOrder: g.sortOrder,
                        createdAt: g.createdAt, updatedAt: g.updatedAt)
        }
        let backupTags = tags.map { t in
            BackupTag(id: t.id, name: t.name, colorHex: t.colorHex,
                      colorHexes: t.colorHexes, createdAt: t.createdAt,
                      updatedAt: t.updatedAt)
        }
        return BackupRecord(
            version: currentVersion, salt: nil, encryptedVaultKey: nil,
            encryptedBackupKey: nil, encryptedBackupKeyLocal: nil,
            createdAt: Date(), appVersion: "1.0",
            items: backupItems, groups: backupGroups, tags: backupTags
        )
    }

    /// Attach password-protected VaultKey to backup (v3 two-layer encryption).
    /// Layer 1: backupKey encrypts VaultKey → encryptedVaultKey
    /// Layer 2a: password encrypts backupKey → encryptedBackupKey (cross-device)
    /// Layer 2b: vaultKey encrypts backupKey → encryptedBackupKeyLocal (same-device)
    static func attachVaultKey(
        to record: inout BackupRecord,
        vaultKey: SymmetricKey,
        password: String
    ) throws {
        let vaultKeyData = vaultKey.withUnsafeBytes { Data($0) }

        // Generate random backup key
        let backupKey = SymmetricKey(size: .bits256)
        let backupKeyData = backupKey.withUnsafeBytes { Data($0) }

        // Layer 1: encrypt VaultKey with backupKey
        let vaultBox = try AES.GCM.seal(vaultKeyData, using: backupKey)
        record.encryptedVaultKey = vaultBox.combined

        // Layer 2a: generate salt, derive key from password, encrypt backupKey
        var salt = Data(count: 32)
        guard salt.withUnsafeMutableBytes({ ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }) == errSecSuccess else { throw BackupError.writeFailed }
        record.salt = salt

        let wrappingKey = deriveKey(password: password, salt: salt)
        let backupBox = try AES.GCM.seal(backupKeyData, using: wrappingKey)
        record.encryptedBackupKey = backupBox.combined

        // Layer 2b: encrypt backupKey with vaultKey (for same-device restore)
        let localBox = try AES.GCM.seal(backupKeyData, using: vaultKey)
        record.encryptedBackupKeyLocal = localBox.combined
    }

    // MARK: - Import

    /// Try decrypting VaultKey using local vaultKey first, return nil if unavailable.
    static func tryDecryptVaultKeyLocal(from record: BackupRecord, vaultKey: SymmetricKey?) -> SymmetricKey? {
        guard let key = vaultKey,
              let combined = record.encryptedVaultKey,
              let localCombined = record.encryptedBackupKeyLocal,
              let backupKeyBox = try? AES.GCM.SealedBox(combined: localCombined),
              let backupKeyData = try? AES.GCM.open(backupKeyBox, using: key),
              let vaultBox = try? AES.GCM.SealedBox(combined: combined),
              let vaultKeyData = try? AES.GCM.open(vaultBox, using: SymmetricKey(data: backupKeyData)) else {
            return nil
        }
        return SymmetricKey(data: vaultKeyData)
    }

    /// Decrypt VaultKey using password.
    static func decryptVaultKey(from record: BackupRecord, password: String) throws -> SymmetricKey {
        guard let salt = record.salt,
              let vaultCombined = record.encryptedVaultKey,
              let backupCombined = record.encryptedBackupKey else {
            throw BackupError.missingVaultKey
        }
        let wrappingKey = deriveKey(password: password, salt: salt)
        let backupBox = try AES.GCM.SealedBox(combined: backupCombined)
        let backupKeyData: Data
        do {
            backupKeyData = try AES.GCM.open(backupBox, using: wrappingKey)
        } catch {
            throw BackupError.wrongPassword
        }
        let backupKey = SymmetricKey(data: backupKeyData)
        let vaultBox = try AES.GCM.SealedBox(combined: vaultCombined)
        let vaultKeyData = try AES.GCM.open(vaultBox, using: backupKey)
        return SymmetricKey(data: vaultKeyData)
    }

    // MARK: - File I/O

    static func readBackup(from url: URL) throws -> BackupRecord {
        let data = try Data(contentsOf: url)
        let record = try JSONDecoder().decode(BackupRecord.self, from: data)
        guard record.version <= currentVersion else { throw BackupError.versionMismatch }
        return record
    }

    // MARK: - Item import

    @MainActor
    static func importBackup(_ record: BackupRecord, into repository: VaultRepository) async throws {
        var groupMap: [UUID: VaultGroup] = [:]
        for bg in record.groups {
            if let ex = repository.groups.first(where: { $0.id == bg.id }) {
                groupMap[bg.id] = ex
            } else if let ex = repository.groups.first(where: { $0.name == bg.name }) {
                groupMap[bg.id] = ex
            } else {
                let ng = VaultGroup(id: bg.id, name: bg.name, colorHex: bg.colorHex,
                                    colorHexes: bg.colorHexes, sortOrder: bg.sortOrder,
                                    createdAt: bg.createdAt, updatedAt: bg.updatedAt)
                repository.appendGroup(ng); groupMap[bg.id] = ng
            }
        }
        var tagMap: [UUID: VaultTag] = [:]
        for bt in record.tags {
            if let ex = repository.tags.first(where: { $0.id == bt.id }) {
                tagMap[bt.id] = ex
            } else if let ex = repository.tags.first(where: { $0.name == bt.name }) {
                tagMap[bt.id] = ex
            } else {
                let nt = VaultTag(id: bt.id, name: bt.name, colorHex: bt.colorHex,
                                  colorHexes: bt.colorHexes, createdAt: bt.createdAt,
                                  updatedAt: bt.updatedAt)
                repository.appendTag(nt); tagMap[bt.id] = nt
            }
        }
        for bi in record.items {
            if let ex = repository.items.first(where: { $0.id == bi.id }), ex.isDeleted {
                ex.isDeleted = false; ex.deletedAt = nil
                ex.title = bi.title; ex.website = bi.website; ex.username = bi.username
                ex.email = bi.email; ex.phone = bi.phone; ex.notePreview = bi.notePreview
                ex.isFavorite = bi.isFavorite; ex.createdAt = bi.createdAt
                ex.updatedAt = bi.updatedAt
                ex.group = bi.groupID.flatMap { groupMap[$0] }
                ex.tags = bi.tagIDs.compactMap { tagMap[$0] }
                continue
            }
            let sr = UUID().uuidString
            repository.storeSecretData(try JSONEncoder().encode(bi.encryptedSecret), for: sr)
            repository.appendItem(VaultItem(
                id: bi.id, title: bi.title, website: bi.website, username: bi.username,
                email: bi.email, phone: bi.phone, notePreview: bi.notePreview,
                secretRef: sr, isFavorite: bi.isFavorite, isDeleted: bi.isDeleted,
                deletedAt: bi.deletedAt, createdAt: bi.createdAt, updatedAt: bi.updatedAt,
                lastUsedAt: bi.lastUsedAt,
                group: bi.groupID.flatMap { groupMap[$0] },
                tags: bi.tagIDs.compactMap { tagMap[$0] }
            ))
        }
    }

    // MARK: - CSV Import

    struct CSVImportItem: Sendable {
        var title: String; var website: String?; var username: String?
        var email: String?; var phone: String?; var password: String?
        var notePreview: String?; var groupName: String?; var tagNames: [String]
    }

    enum CSVImportError: Error {
        case emptyFile
        case missingHeader
        case invalidColumnCount
        case malformedRow(Int)
    }

    static func parseCSV(from url: URL) throws -> [CSVImportItem] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = parseCSVLines(content)
        guard !lines.isEmpty else { throw CSVImportError.emptyFile }

        let header = lines[0]
        let expectedHeader = ["Title", "Website", "Username", "Email", "Phone", "Password", "Note", "Group", "Tags"]
        guard header == expectedHeader else { throw CSVImportError.missingHeader }

        var result: [CSVImportItem] = []
        for (_, row) in lines.dropFirst().enumerated() {
            guard row.count == expectedHeader.count else { throw CSVImportError.invalidColumnCount }
            guard !row[0].isEmpty else { continue }

            let tagNames = row[8].isEmpty ? [] : row[8].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            result.append(CSVImportItem(
                title: row[0],
                website: row[1].isEmpty ? nil : row[1],
                username: row[2].isEmpty ? nil : row[2],
                email: row[3].isEmpty ? nil : row[3],
                phone: row[4].isEmpty ? nil : row[4],
                password: row[5].isEmpty ? nil : row[5],
                notePreview: row[6].isEmpty ? nil : row[6],
                groupName: row[7].isEmpty ? nil : row[7],
                tagNames: tagNames
            ))
        }
        return result
    }

    private static func parseCSVLines(_ content: String) -> [[String]] {
        var lines: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in content {
            switch char {
            case "\"":
                if inQuotes {
                    inQuotes = false
                } else {
                    inQuotes = true
                }
            case ",":
                if inQuotes {
                    currentField.append(char)
                } else {
                    currentRow.append(currentField)
                    currentField = ""
                }
            case "\n", "\r\n":
                if inQuotes {
                    currentField.append(char)
                } else {
                    currentRow.append(currentField)
                    if !currentRow.isEmpty && !(currentRow.count == 1 && currentRow[0].isEmpty) {
                        lines.append(currentRow)
                    }
                    currentRow = []
                    currentField = ""
                }
            case "\r":
                break
            default:
                currentField.append(char)
            }
        }

        currentRow.append(currentField)
        if !currentRow.isEmpty && !(currentRow.count == 1 && currentRow[0].isEmpty) {
            lines.append(currentRow)
        }
        return lines
    }

    // MARK: - CSV Export

    @MainActor
    static func exportCSV(
        items: [VaultItem],
        repository: VaultRepository
    ) async throws -> String {
        var rows: [String] = ["Title,Website,Username,Email,Phone,Password,Note,Group,Tags"]

        for item in items {
            let title = escapeCSV(item.title)
            let website = escapeCSV(item.website ?? "")
            let username = escapeCSV(item.username ?? "")
            let email = escapeCSV(item.email ?? "")
            let phone = escapeCSV(item.phone ?? "")
            var password = ""
            do {
                let secret = try await repository.revealSecret(id: item.id, reason: "CSV 导出")
                password = escapeCSV(secret.password)
            } catch {
                password = escapeCSV("[认证失败]")
            }
            let note = escapeCSV(item.notePreview ?? "")
            let group = escapeCSV(item.group?.name ?? "")
            let tags = escapeCSV(item.tags.map(\.name).joined(separator: ";"))
            rows.append("\(title),\(website),\(username),\(email),\(phone),\(password),\(note),\(group),\(tags)")
        }
        return rows.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - Private

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let pwd = SymmetricKey(data: password.data(using: .utf8)!)
        var derived = Data()
        var u = salt
        u.append(contentsOf: withUnsafeBytes(of: UInt32(1).bigEndian) { Data($0) })
        var t = Data(HMAC<SHA256>.authenticationCode(for: u, using: pwd))
        var prev = t
        for _ in 1..<100_000 {
            prev = Data(HMAC<SHA256>.authenticationCode(for: prev, using: pwd))
            for i in 0..<t.count { t[i] ^= prev[i] }
        }
        derived.append(t)
        return SymmetricKey(data: derived.prefix(32))
    }
}
