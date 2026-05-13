import Foundation
import SwiftData

@Model
final class VaultGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String?
    var colorHexes: [String]?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \VaultItem.group)
    var items: [VaultItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        colorHexes: [String]? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [VaultItem] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.colorHexes = colorHexes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }
}