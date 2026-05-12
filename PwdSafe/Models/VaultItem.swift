import Foundation
import SwiftData

@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var website: String?
    var username: String?
    var notePreview: String?
    var iconName: String?
    var secretRef: String
    var isFavorite: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    @Relationship(deleteRule: .nullify)
    var group: VaultGroup?

    @Relationship
    var tags: [VaultTag]

    init(
        id: UUID = UUID(),
        title: String,
        website: String? = nil,
        username: String? = nil,
        notePreview: String? = nil,
        iconName: String? = nil,
        secretRef: String = "",
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        group: VaultGroup? = nil,
        tags: [VaultTag] = []
    ) {
        self.id = id
        self.title = title
        self.website = website
        self.username = username
        self.notePreview = notePreview
        self.iconName = iconName
        self.secretRef = secretRef
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.group = group
        self.tags = tags
    }
}