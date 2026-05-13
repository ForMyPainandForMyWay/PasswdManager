import Foundation

struct BackupRecord: Codable, Sendable {
    var version: Int
    var createdAt: Date
    var appVersion: String
    var items: [BackupItem]
    var groups: [BackupGroup]
    var tags: [BackupTag]
}

struct BackupItem: Codable, Sendable {
    var id: UUID
    var title: String
    var website: String?
    var username: String?
    var email: String?
    var phone: String?
    var notePreview: String?
    var isFavorite: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var groupID: UUID?
    var tagIDs: [UUID]
    var encryptedSecret: EncryptedSecret
}

struct BackupGroup: Codable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String?
    var colorHexes: [String]?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

struct BackupTag: Codable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String?
    var colorHexes: [String]?
    var createdAt: Date
    var updatedAt: Date
}

enum BackupError: Error {
    case invalidFormat
    case versionMismatch
    case writeFailed
    case readFailed
    case missingVaultKey
}

struct BackupService: Sendable {

    static let currentVersion = 1
    static let fileExtension = "pwdsafe-backup"
    static let utiType = "com.pwdsafe.backup"

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

            let backupItem = BackupItem(
                id: item.id,
                title: item.title,
                website: item.website,
                username: item.username,
                email: item.email,
                phone: item.phone,
                notePreview: item.notePreview,
                isFavorite: item.isFavorite,
                isDeleted: item.isDeleted,
                deletedAt: item.deletedAt,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                groupID: item.group?.id,
                tagIDs: item.tags.map(\.id),
                encryptedSecret: encrypted
            )
            backupItems.append(backupItem)
        }

        let backupGroups = groups.map { group in
            BackupGroup(
                id: group.id,
                name: group.name,
                colorHex: group.colorHex,
                colorHexes: group.colorHexes,
                sortOrder: group.sortOrder,
                createdAt: group.createdAt,
                updatedAt: group.updatedAt
            )
        }

        let backupTags = tags.map { tag in
            BackupTag(
                id: tag.id,
                name: tag.name,
                colorHex: tag.colorHex,
                colorHexes: tag.colorHexes,
                createdAt: tag.createdAt,
                updatedAt: tag.updatedAt
            )
        }

        return BackupRecord(
            version: currentVersion,
            createdAt: Date(),
            appVersion: "1.0",
            items: backupItems,
            groups: backupGroups,
            tags: backupTags
        )
    }

    static func writeBackup(_ record: BackupRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    static func readBackup(from url: URL) throws -> BackupRecord {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let record = try decoder.decode(BackupRecord.self, from: data)

        guard record.version <= currentVersion else {
            throw BackupError.versionMismatch
        }

        return record
    }

    @MainActor
    static func importBackup(
        _ record: BackupRecord,
        into repository: VaultRepository
    ) async throws {
        let existingGroupIDs = Set(repository.groups.map(\.id))
        for group in record.groups {
            if !existingGroupIDs.contains(group.id) {
                repository.appendGroup(VaultGroup(
                    id: group.id,
                    name: group.name,
                    colorHex: group.colorHex,
                    colorHexes: group.colorHexes,
                    sortOrder: group.sortOrder,
                    createdAt: group.createdAt,
                    updatedAt: group.updatedAt
                ))
            }
        }

        let existingTagIDs = Set(repository.tags.map(\.id))
        for tag in record.tags {
            if !existingTagIDs.contains(tag.id) {
                repository.appendTag(VaultTag(
                    id: tag.id,
                    name: tag.name,
                    colorHex: tag.colorHex,
                    colorHexes: tag.colorHexes,
                    createdAt: tag.createdAt,
                    updatedAt: tag.updatedAt
                ))
            }
        }

        let groupMap = Dictionary(uniqueKeysWithValues: repository.groups.map { ($0.id, $0) })
        let tagMap = Dictionary(uniqueKeysWithValues: repository.tags.map { ($0.id, $0) })

        for backupItem in record.items {
            if let existing = repository.items.first(where: { $0.id == backupItem.id }) {
                if existing.isDeleted {
                    existing.isDeleted = false
                    existing.deletedAt = nil
                    existing.title = backupItem.title
                    existing.website = backupItem.website
                    existing.username = backupItem.username
                    existing.email = backupItem.email
                    existing.phone = backupItem.phone
                    existing.notePreview = backupItem.notePreview
                    existing.isFavorite = backupItem.isFavorite
                    existing.createdAt = backupItem.createdAt
                    existing.updatedAt = backupItem.updatedAt
                    existing.group = backupItem.groupID.flatMap { groupMap[$0] }
                    existing.tags = backupItem.tagIDs.compactMap { tagMap[$0] }
                }
                continue
            }

            let secretRef = UUID().uuidString
            let encryptedData = try JSONEncoder().encode(backupItem.encryptedSecret)
            repository.storeSecretData(encryptedData, for: secretRef)

            let item = VaultItem(
                id: backupItem.id,
                title: backupItem.title,
                website: backupItem.website,
                username: backupItem.username,
                email: backupItem.email,
                phone: backupItem.phone,
                notePreview: backupItem.notePreview,
                secretRef: secretRef,
                isFavorite: backupItem.isFavorite,
                isDeleted: backupItem.isDeleted,
                deletedAt: backupItem.deletedAt,
                createdAt: backupItem.createdAt,
                updatedAt: backupItem.updatedAt,
                group: backupItem.groupID.flatMap { groupMap[$0] },
                tags: backupItem.tagIDs.compactMap { tagMap[$0] }
            )
            repository.appendItem(item)
        }
    }
}