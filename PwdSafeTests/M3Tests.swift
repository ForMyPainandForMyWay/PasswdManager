import Testing
import Foundation
import CryptoKit
@testable import PwdSafe

struct PasswordGeneratorTests {

    @Test func testGenerateDefaultOptions() {
        let password = PasswordGenerator.generate()
        #expect(password.count == 16)
    }

    @Test func testGenerateCustomLength() {
        let options = PasswordGenerator.Options(length: 24)
        let password = PasswordGenerator.generate(options: options)
        #expect(password.count == 24)
    }

    @Test func testGenerateMinLength() {
        let options = PasswordGenerator.Options(length: 4)
        let password = PasswordGenerator.generate(options: options)
        #expect(password.count == 4)
    }

    @Test func testGenerateMaxLength() {
        let options = PasswordGenerator.Options(length: 64)
        let password = PasswordGenerator.generate(options: options)
        #expect(password.count == 64)
    }

    @Test func testGenerateOnlyLowercase() {
        let options = PasswordGenerator.Options(
            length: 32,
            includeUppercase: false,
            includeLowercase: true,
            includeDigits: false,
            includeSymbols: false
        )
        let password = PasswordGenerator.generate(options: options)
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        #expect(password.allSatisfy { lowercase.contains($0) })
    }

    @Test func testGenerateOnlyDigits() {
        let options = PasswordGenerator.Options(
            length: 20,
            includeUppercase: false,
            includeLowercase: false,
            includeDigits: true,
            includeSymbols: false
        )
        let password = PasswordGenerator.generate(options: options)
        let digits = "0123456789"
        #expect(password.allSatisfy { digits.contains($0) })
    }

    @Test func testGenerateContainsAllRequiredTypes() {
        let options = PasswordGenerator.Options(
            length: 32,
            includeUppercase: true,
            includeLowercase: true,
            includeDigits: true,
            includeSymbols: true
        )
        let password = PasswordGenerator.generate(options: options)
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let digits = "0123456789"
        let symbols = "!@#$%^&*()-_=+[]{}|;:,.<>?/~`"
        #expect(password.contains(where: { uppercase.contains($0) }))
        #expect(password.contains(where: { lowercase.contains($0) }))
        #expect(password.contains(where: { digits.contains($0) }))
        #expect(password.contains(where: { symbols.contains($0) }))
    }

    @Test func testGenerateIsRandom() {
        let passwords = (0..<10).map { _ in PasswordGenerator.generate() }
        let unique = Set(passwords)
        #expect(unique.count == 10)
    }

    @Test func testOptionsInvalidWhenNoCharset() {
        let options = PasswordGenerator.Options(
            includeUppercase: false,
            includeLowercase: false,
            includeDigits: false,
            includeSymbols: false
        )
        #expect(!options.isValid)
    }

    @Test func testOptionsInvalidWhenLengthTooShort() {
        let options = PasswordGenerator.Options(length: 3)
        #expect(!options.isValid)
    }

    @Test func testStrengthVeryWeak() {
        let strength = PasswordGenerator.strength(of: "abc")
        #expect(strength == .veryWeak)
    }

    @Test func testStrengthWeak() {
        let strength = PasswordGenerator.strength(of: "abcdef")
        #expect(strength == .weak)
    }

    @Test func testStrengthFair() {
        let strength = PasswordGenerator.strength(of: "Abcdef1234")
        #expect(strength == .fair)
    }

    @Test func testStrengthStrong() {
        let options = PasswordGenerator.Options(length: 16)
        let password = PasswordGenerator.generate(options: options)
        let strength = PasswordGenerator.strength(of: password)
        #expect(strength >= .strong)
    }

    @Test func testStrengthVeryStrong() {
        let options = PasswordGenerator.Options(length: 24)
        let password = PasswordGenerator.generate(options: options)
        let strength = PasswordGenerator.strength(of: password)
        #expect(strength == .veryStrong)
    }

    @Test func testEntropyBits() {
        let entropy = PasswordGenerator.entropyBits(of: "Abc123!@")
        #expect(entropy > 0)
    }

    @Test func testEntropyBitsEmptyPassword() {
        let entropy = PasswordGenerator.entropyBits(of: "")
        #expect(entropy == 0)
    }

    @Test func testStrengthComparison() {
        #expect(PasswordGenerator.Strength.veryWeak < PasswordGenerator.Strength.weak)
        #expect(PasswordGenerator.Strength.weak < PasswordGenerator.Strength.fair)
        #expect(PasswordGenerator.Strength.fair < PasswordGenerator.Strength.strong)
        #expect(PasswordGenerator.Strength.strong < PasswordGenerator.Strength.veryStrong)
    }
}

@MainActor
@Suite(.serialized)
struct BackupServiceTests {

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
        try await repository.initializeVault()
        await repository.loadSampleData()
    }

    @Test mutating func testExportBackupProducesValidRecord() async throws {
        let record = try await repository.exportBackup()

        #expect(record.version == 1)
        #expect(record.items.count == 8)
        #expect(record.groups.count == 3)
        #expect(record.tags.count == 3)
        #expect(record.appVersion == "1.0")
    }

    @Test mutating func testExportBackupIncludesEncryptedSecrets() async throws {
        let record = try await repository.exportBackup()

        for item in record.items {
            #expect(!item.encryptedSecret.ciphertext.isEmpty)
            #expect(!item.encryptedSecret.nonce.isEmpty)
            #expect(!item.encryptedSecret.tag.isEmpty)
            #expect(item.encryptedSecret.algorithm == "AES-256-GCM")
        }
    }

    @Test mutating func testExportBackupItemHasMetadata() async throws {
        let record = try await repository.exportBackup()
        let ghItem = record.items.first { $0.title == "GitHub" }
        #expect(ghItem != nil)
        #expect(ghItem?.website == "https://github.com")
        #expect(ghItem?.username == "mygithub")
        #expect(ghItem?.isDeleted == false)
    }

    @Test mutating func testExportBackupIncludesDeletedItems() async throws {
        let record = try await repository.exportBackup()
        let deletedItem = record.items.first { $0.isDeleted }
        #expect(deletedItem != nil)
        #expect(deletedItem?.title == "已删除的旧账号")
    }

    @Test mutating func testBackupRecordCodableRoundtrip() async throws {
        let record = try await repository.exportBackup()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BackupRecord.self, from: data)

        #expect(decoded.version == record.version)
        #expect(decoded.items.count == record.items.count)
        #expect(decoded.groups.count == record.groups.count)
        #expect(decoded.tags.count == record.tags.count)
    }

    @Test mutating func testImportBackupPreservesData() async throws {
        let record = try await repository.exportBackup()

        let newRepo = VaultRepository(
            authService: MockAuthService(),
            cryptoService: AESCryptoService(),
            keychainStore: MockKeychainStore()
        )
        try await newRepo.initializeVault()

        try await BackupService.importBackup(record, into: newRepo)

        #expect(newRepo.items.count == 8)
        #expect(newRepo.groups.count == 3)
        #expect(newRepo.tags.count == 3)
        #expect(newRepo.allItems.count == 7)
        #expect(newRepo.trashedItems.count == 1)
    }

    @Test mutating func testImportBackupPasswordsDecryptable() async throws {
        let record = try await repository.exportBackup()

        let sourceRepo = VaultRepository(
            authService: MockAuthService(),
            cryptoService: AESCryptoService(),
            keychainStore: mockKeychain
        )
        try await sourceRepo.initializeVault()
        try await BackupService.importBackup(record, into: sourceRepo)

        let ghItem = sourceRepo.allItems.first { $0.title == "GitHub" }!
        let secret = try await sourceRepo.revealSecret(id: ghItem.id)
        #expect(secret.password == "GitHub!Dev99")
    }

    @Test mutating func testImportBackupMergesGroups() async throws {
        let record = try await repository.exportBackup()

        let newRepo = VaultRepository(
            authService: MockAuthService(),
            cryptoService: AESCryptoService(),
            keychainStore: MockKeychainStore()
        )
        try await newRepo.initializeVault()
        newRepo.createGroup(name: "自定义分组", colorHex: "#000000")

        try await BackupService.importBackup(record, into: newRepo)

        #expect(newRepo.groups.count >= 3)
        #expect(newRepo.groups.contains(where: { $0.name == "自定义分组" }))
        #expect(newRepo.groups.contains(where: { $0.name == "社交" }))
    }

    @Test func testBackupReadWriteRoundtrip() throws {
        let original = BackupRecord(
            version: 1,
            createdAt: Date(),
            appVersion: "1.0",
            items: [],
            groups: [
                BackupGroup(id: UUID(), name: "Test", colorHex: nil, sortOrder: 0, createdAt: Date(), updatedAt: Date())
            ],
            tags: []
        )

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_backup.pwd")
        try BackupService.writeBackup(original, to: tempURL)
        let decoded = try BackupService.readBackup(from: tempURL)

        #expect(decoded.version == 1)
        #expect(decoded.groups.count == 1)
        #expect(decoded.groups.first?.name == "Test")
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func testReadBackupVersionMismatch() throws {
        let json = """
        {"version":999,"createdAt":0,"appVersion":"1.0","items":[],"groups":[],"tags":[]}
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("bad_version.pwd")
        try json.write(to: tempURL, atomically: true, encoding: .utf8)

        #expect(throws: BackupError.versionMismatch) {
            try BackupService.readBackup(from: tempURL)
        }
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func testReadBackupInvalidFormat() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.pwd")
        try "not json".write(to: tempURL, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try BackupService.readBackup(from: tempURL)
        }
        try? FileManager.default.removeItem(at: tempURL)
    }
}

struct SettingsDefaultsTests {

    @Test func testAuthPolicyDefault() {
        let defaults = UserDefaults.standard
        let policy = defaults.string(forKey: "authPolicy")
        #expect(policy == nil || policy == "session5min")
    }

    @Test func testClipboardTimeoutDefault() {
        let defaults = UserDefaults.standard
        let timeout = defaults.integer(forKey: "clipboardTimeout")
        #expect(timeout == 0 || timeout == 30)
    }

    @Test func testAutoLockTimeoutDefault() {
        let defaults = UserDefaults.standard
        let timeout = defaults.integer(forKey: "autoLockTimeout")
        #expect(timeout == 0 || timeout == 5)
    }

    @Test func testTrashAutoCleanupDefault() {
        let defaults = UserDefaults.standard
        let cleanup = defaults.integer(forKey: "trashAutoCleanup")
        #expect(cleanup == 0)
    }

    @Test func testAuthPolicyAllCases() {
        let cases = AuthPolicy.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.everyTime))
        #expect(cases.contains(.session5min))
    }

    @Test func testClipboardTimeoutAllCases() {
        let cases = ClipboardTimeout.allCases
        #expect(cases.count == 4)
    }

    @Test func testAutoLockTimeoutAllCases() {
        let cases = AutoLockTimeout.allCases
        #expect(cases.count == 4)
    }

    @Test func testTrashAutoCleanupAllCases() {
        let cases = TrashAutoCleanup.allCases
        #expect(cases.count == 3)
    }
}