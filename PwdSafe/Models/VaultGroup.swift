import Foundation

final class VaultGroup: Identifiable {
    var id: UUID
    var name: String
    var colorHex: String?
    var colorHexes: [String]?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        colorHexes: [String]? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.colorHexes = colorHexes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}