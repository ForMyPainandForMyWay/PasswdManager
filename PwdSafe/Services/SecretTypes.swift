import Foundation

struct SecretPayload: Codable, Sendable {
    var password: String
    var secureNote: String?
    var totpSeed: String?
    var customFields: [SecretField]
}

struct SecretField: Codable, Hashable, Sendable {
    var name: String
    var value: String
    var isHidden: Bool
}

struct EncryptedSecret: Codable, Sendable {
    var version: Int
    var algorithm: String
    var keyID: String
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}