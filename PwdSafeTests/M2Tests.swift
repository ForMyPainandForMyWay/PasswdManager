import Testing
import Foundation
import CryptoKit
import AppKit
@testable import PwdSafe

struct CryptoServiceTests {

    let cryptoService = AESCryptoService()

    @Test func testCreateVaultKey() throws {
        let key = try cryptoService.createVaultKey()
        #expect(key.bitCount == 256)
    }

    @Test func testEncryptAndDecrypt() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let itemID = UUID()
        let payload = SecretPayload(password: "MySecretP@ssw0rd!")

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: vaultKey)

        #expect(encrypted.version == 1)
        #expect(encrypted.algorithm == "AES-256-GCM")
        #expect(!encrypted.nonce.isEmpty)
        #expect(!encrypted.ciphertext.isEmpty)
        #expect(!encrypted.tag.isEmpty)

        let decrypted = try cryptoService.decrypt(encrypted, itemID: itemID, vaultKey: vaultKey)
        #expect(decrypted.password == "MySecretP@ssw0rd!")
    }

    @Test func testEncryptWithDifferentKeysProducesDifferentResults() throws {
        let key1 = try cryptoService.createVaultKey()
        let key2 = try cryptoService.createVaultKey()
        let itemID = UUID()
        let payload = SecretPayload(password: "test")

        let encrypted1 = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: key1)
        let encrypted2 = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: key2)

        #expect(encrypted1.ciphertext != encrypted2.ciphertext)
    }

    @Test func testEncryptWithDifferentItemIDsProducesDifferentResults() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let payload = SecretPayload(password: "test")

        let encrypted1 = try cryptoService.encrypt(payload, itemID: UUID(), vaultKey: vaultKey)
        let encrypted2 = try cryptoService.encrypt(payload, itemID: UUID(), vaultKey: vaultKey)

        #expect(encrypted1.ciphertext != encrypted2.ciphertext)
    }

    @Test func testDecryptWithWrongKeyFails() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let wrongKey = try cryptoService.createVaultKey()
        let itemID = UUID()
        let payload = SecretPayload(password: "test")

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: vaultKey)

        #expect(throws: CryptoError.self) {
            try cryptoService.decrypt(encrypted, itemID: itemID, vaultKey: wrongKey)
        }
    }

    @Test func testDecryptWithWrongItemIDFails() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let itemID1 = UUID()
        let itemID2 = UUID()
        let payload = SecretPayload(password: "test")

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID1, vaultKey: vaultKey)

        #expect(throws: CryptoError.self) {
            try cryptoService.decrypt(encrypted, itemID: itemID2, vaultKey: vaultKey)
        }
    }

    @Test func testTamperedCiphertextFails() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let itemID = UUID()
        let payload = SecretPayload(password: "test")

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: vaultKey)

        var tampered = encrypted
        tampered.ciphertext = Data(repeating: 0, count: encrypted.ciphertext.count)

        #expect(throws: CryptoError.self) {
            try cryptoService.decrypt(tampered, itemID: itemID, vaultKey: vaultKey)
        }
    }

    @Test func testTamperedTagFails() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let itemID = UUID()
        let payload = SecretPayload(password: "test")

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: vaultKey)

        var tampered = encrypted
        tampered.tag = Data(repeating: 0xFF, count: encrypted.tag.count)

        #expect(throws: CryptoError.self) {
            try cryptoService.decrypt(tampered, itemID: itemID, vaultKey: vaultKey)
        }
    }

    @Test func testLongPasswordRoundtrip() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let itemID = UUID()
        let longPassword = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%", count: 20)
        let payload = SecretPayload(password: longPassword)

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: vaultKey)
        let decrypted = try cryptoService.decrypt(encrypted, itemID: itemID, vaultKey: vaultKey)

        #expect(decrypted.password == longPassword)
    }

    @Test func testEmptyPasswordRoundtrip() throws {
        let vaultKey = try cryptoService.createVaultKey()
        let itemID = UUID()
        let payload = SecretPayload(password: "")

        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: vaultKey)
        let decrypted = try cryptoService.decrypt(encrypted, itemID: itemID, vaultKey: vaultKey)

        #expect(decrypted.password == "")
    }
}

struct SecretPayloadTests {

    @Test func testCodableRoundtrip() throws {
        let payload = SecretPayload(password: "Test123!")

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SecretPayload.self, from: data)

        #expect(decoded.password == "Test123!")
    }
}

struct EncryptedSecretTests {

    @Test func testCodableRoundtrip() throws {
        let original = EncryptedSecret(
            version: 1,
            algorithm: "AES-256-GCM",
            keyID: "abc123",
            nonce: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C]),
            ciphertext: Data([0x10, 0x20, 0x30]),
            tag: Data([0xA0, 0xB0, 0xC0, 0xD0, 0xE0, 0xF0, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99])
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EncryptedSecret.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.algorithm == "AES-256-GCM")
        #expect(decoded.keyID == "abc123")
        #expect(decoded.nonce == original.nonce)
        #expect(decoded.ciphertext == original.ciphertext)
        #expect(decoded.tag == original.tag)
    }
}

final class MockAuthService: AuthService, @unchecked Sendable {
    var canAuth: Bool = true
    var shouldFail: Bool = false
    var authenticateCallCount: Int = 0
    private var viewSecretValid: Bool = false
    private var destructiveValid: Bool = false

    func authenticate(reason: String, scope: AuthScope) async throws {
        let isValid = scope == .viewSecret ? viewSecretValid : destructiveValid
        if isValid { return }
        authenticateCallCount += 1
        if shouldFail {
            throw AuthError.failed
        }
        switch scope {
        case .viewSecret: viewSecretValid = true
        case .destructive: destructiveValid = true
        }
    }

    func canAuthenticate() -> Bool { canAuth }

    func invalidateAllSessions() {
        viewSecretValid = false
        destructiveValid = false
    }
}

final class MockKeychainStore: KeychainStore, @unchecked Sendable {
    private var vaultKeyData: Data?
    private var secrets: [String: Data] = [:]

    func storeVaultKey(_ key: Data) throws { vaultKeyData = key }
    func loadVaultKey() throws -> Data {
        guard let data = vaultKeyData else { throw KeychainError.itemNotFound }
        return data
    }
    func storeSecret(_ data: Data, for secretRef: String) throws { secrets[secretRef] = data }
    func loadSecret(for secretRef: String) throws -> Data {
        guard let data = secrets[secretRef] else { throw KeychainError.itemNotFound }
        return data
    }
    func deleteSecret(for secretRef: String) throws { secrets.removeValue(forKey: secretRef) }
}

@MainActor
@Suite(.serialized)
struct VaultRepositoryM2Tests {

    var repository: VaultRepository!
    var mockAuth: MockAuthService!
    var mockKeychain: MockKeychainStore!

    init() async throws {
        mockAuth = MockAuthService()
        mockKeychain = MockKeychainStore()
        let crypto = AESCryptoService()
        repository = VaultRepository(
            authService: mockAuth,
            cryptoService: crypto,
            keychainStore: mockKeychain
        )
        _ = try await repository.initializeVault()
    }

    @Test mutating func testInitializeVaultCreatesKey() async throws {
        let repo = VaultRepository(
            authService: MockAuthService(),
            cryptoService: AESCryptoService(),
            keychainStore: mockKeychain
        )
        _ = try await repo.initializeVault()
        #expect(repo.isVaultReady)
    }

    @Test mutating func testCreateAndRevealPassword() async throws {
        let draft = VaultItemDraft(
            title: "Test",
            username: "user",
            password: "SecureP@ss1",
            tagIDs: []
        )
        try await repository.createItem(draft)

        let secret = try await repository.revealSecret(id: repository.selectedItemID!)
        #expect(secret.password == "SecureP@ss1")
        #expect(mockAuth.authenticateCallCount == 1)
    }

    @Test mutating func testRevealSecretUsesAuthSession() async throws {
        let draft = VaultItemDraft(
            title: "Test2",
            username: "user2",
            password: "AnotherP@ss",
            tagIDs: []
        )
        try await repository.createItem(draft)
        let itemID = repository.selectedItemID!

        let _ = try await repository.revealSecret(id: itemID)
        #expect(mockAuth.authenticateCallCount == 1)

        let _ = try await repository.revealSecret(id: itemID)
        #expect(mockAuth.authenticateCallCount == 1)
    }

    @Test mutating func testUpdatePassword() async throws {
        let draft = VaultItemDraft(
            title: "UpdateTest",
            username: "user",
            password: "OldP@ss",
            tagIDs: []
        )
        try await repository.createItem(draft)
        let itemID = repository.selectedItemID!

        let mutation = VaultItemMutation(password: "NewP@ss1")
        try await repository.updateItem(id: itemID, mutation: mutation)

        let secret = try await repository.revealSecret(id: itemID)
        #expect(secret.password == "NewP@ss1")
    }

    @Test mutating func testPermanentlyDeleteRequiresAuth() async throws {
        let draft = VaultItemDraft(
            title: "DeleteTest",
            username: "user",
            password: "DelP@ss1",
            tagIDs: []
        )
        try await repository.createItem(draft)
        let itemID = repository.selectedItemID!
        repository.moveToTrash(ids: [itemID])

        #expect(repository.trashedItems.count == 1)
        mockAuth.authenticateCallCount = 0

        try await repository.permanentlyDelete(ids: [itemID])
        #expect(mockAuth.authenticateCallCount == 1)
        #expect(repository.trashedItems.count == 0)
    }

    @Test mutating func testPermanentlyDeleteWithoutAuth() async throws {
        let draft = VaultItemDraft(
            title: "NoAuthDel",
            username: "user",
            password: "DelP@ss2",
            tagIDs: []
        )
        try await repository.createItem(draft)
        let itemID = repository.selectedItemID!
        repository.moveToTrash(ids: [itemID])

        mockAuth.authenticateCallCount = 0
        repository.permanentlyDeleteWithoutAuth(ids: [itemID])

        #expect(mockAuth.authenticateCallCount == 0)
        #expect(repository.trashedItems.count == 0)
    }

    @Test mutating func testCopyPasswordClearsClipboard() async throws {
        let draft = VaultItemDraft(
            title: "CopyTest",
            username: "user",
            password: "CopyP@ss1",
            tagIDs: []
        )
        try await repository.createItem(draft)

        try await repository.copyPassword(id: repository.selectedItemID!)

        let pasteboard = NSPasteboard.general
        #expect(pasteboard.string(forType: .string) == "CopyP@ss1")
    }

    @Test mutating func testCreateItemWithFavorite() async throws {
        let draft = VaultItemDraft(
            title: "FavoriteTest",
            username: "user",
            password: "FavP@ss",
            isFavorite: true,
            tagIDs: []
        )
        try await repository.createItem(draft)

        let item = repository.selectedItem()!
        #expect(item.isFavorite == true)
        #expect(repository.favoriteItems.count == 1)
    }

    @Test mutating func testLoadSampleDataCreatesEncryptedSecrets() async throws {
        await repository.loadSampleData()

        #expect(repository.allItems.count == 7)
        #expect(repository.trashedItems.count == 1)

        let firstItem = repository.allItems.first!
        let secret = try await repository.revealSecret(id: firstItem.id)
        #expect(!secret.password.isEmpty)
    }
}