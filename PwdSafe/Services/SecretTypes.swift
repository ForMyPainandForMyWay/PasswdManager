import Foundation

struct PasswordHistoryEntry: Codable, Hashable, Sendable {
    var timestamp: Date
    var passwordHash: String
}

struct SecretPayload: Codable, Sendable {
    var password: String
    var passwordHistory: [PasswordHistoryEntry] = []
}

struct EncryptedSecret: Codable, Sendable {
    var version: Int
    var algorithm: String
    var keyID: String
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}