import Foundation
import SwiftData

@Model
final class VaultTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String?
    var colorHexes: [String]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        colorHexes: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.colorHexes = colorHexes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}