import Foundation
import Observation
import CryptoKit
import os

enum VaultError: Error {
    case notInitialized
    case itemNotFound
}

private struct PersistedVaultData: Codable {
    var items: [PersistedItem]
    var groups: [PersistedGroup]
    var tags: [PersistedTag]
}

private struct PersistedItem: Codable {
    var id: UUID; var title: String; var website: String?; var username: String?
    var email: String?; var phone: String?; var notePreview: String?
    var secretRef: String; var isFavorite: Bool; var isDeleted: Bool
    var deletedAt: Date?; var createdAt: Date; var updatedAt: Date
    var lastUsedAt: Date?; var passwordHistoryCount: Int = 0; var groupID: UUID?; var tagIDs: [UUID]
}

private struct PersistedGroup: Codable {
    var id: UUID; var name: String; var colorHex: String?; var colorHexes: [String]?
    var sortOrder: Int; var createdAt: Date; var updatedAt: Date
}

private struct PersistedTag: Codable {
    var id: UUID; var name: String; var colorHex: String?; var colorHexes: [String]?
    var createdAt: Date; var updatedAt: Date
}

@MainActor
@Observable
final class VaultRepository {
    private let authService: AuthService
    private let cryptoService: CryptoService
    private let keychainStore: KeychainStore
    private let clipboardCleaner: ClipboardCleaner

    private(set) var items: [VaultItem] = []
    private(set) var groups: [VaultGroup] = []
    private(set) var tags: [VaultTag] = []
    private(set) var selectedItemID: UUID?
    var searchQuery: String = ""
    var isEditorPresented: Bool = false
    var editingItem: VaultItem?
    var newItemStartAsFavorite: Bool = false
    var isLocked: Bool = true
    var isVaultReady: Bool = false
    private var vaultKey: SymmetricKey?
    private var memorySecrets: [String: Data] = [:]

    init(
        authService: AuthService = LAAuthService(),
        cryptoService: CryptoService = AESCryptoService(),
        keychainStore: KeychainStore = KeychainStoreImpl(),
        clipboardCleaner: ClipboardCleaner = ClipboardCleaner()
    ) {
        self.authService = authService
        self.cryptoService = cryptoService
        self.keychainStore = keychainStore
        self.clipboardCleaner = clipboardCleaner
    }

    var allItems: [VaultItem] { items.filter { !$0.isDeleted } }
    var favoriteItems: [VaultItem] { allItems.filter { $0.isFavorite } }
    var trashedItems: [VaultItem] { items.filter { $0.isDeleted } }

    var filteredItems: [VaultItem] {
        if searchQuery.isEmpty { return allItems }
        let query = searchQuery.lowercased()
        return allItems.filter { item in
            item.title.lowercased().contains(query)
            || (item.website?.lowercased().contains(query) ?? false)
            || (item.username?.lowercased().contains(query) ?? false)
            || (item.notePreview?.lowercased().contains(query) ?? false)
            || (item.group?.name.lowercased().contains(query) ?? false)
            || item.tags.contains { $0.name.lowercased().contains(query) }
        }
    }

    func items(for group: VaultGroup) -> [VaultItem] { allItems.filter { $0.group?.id == group.id } }
    func items(for tag: VaultTag) -> [VaultItem] { allItems.filter { $0.tags.contains(where: { $0.id == tag.id }) } }
    func selectItem(_ id: UUID?) { selectedItemID = id }
    func selectedItem() -> VaultItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    // MARK: - Vault initialization

    func initializeVault() async throws {
        if let keyData = try? keychainStore.loadVaultKey() {
            vaultKey = SymmetricKey(data: keyData)
            isVaultReady = true
            return
        }

        let key = try cryptoService.createVaultKey()
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychainStore.storeVaultKey(keyData)
        vaultKey = key
        isVaultReady = true

        // Clean up any stale metadata from a previous key reset
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }

    func loadPersistedData() {
        if hasPersistedData {
            guard let data = try? Data(contentsOf: metadataURL),
                  let persisted = try? JSONDecoder().decode(PersistedVaultData.self, from: data),
                  !persisted.items.isEmpty || !persisted.groups.isEmpty || !persisted.tags.isEmpty
            else {
                try? FileManager.default.removeItem(at: metadataURL)
                return
            }
            loadMetadata()
        }
    }

    // MARK: - Item CRUD

    func createItem(_ draft: VaultItemDraft) async throws {
        guard let key = vaultKey else { throw VaultError.notInitialized }
        let secretRef = UUID().uuidString
        let payload = SecretPayload(password: draft.password)
        let itemID = UUID()
        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: key)
        let encryptedData = try JSONEncoder().encode(encrypted)
        try storeSecretData(encryptedData, for: secretRef)
        let item = VaultItem(
            id: itemID, title: draft.title, website: draft.website,
            username: draft.username, email: draft.email, phone: draft.phone,
            notePreview: draft.notePreview, secretRef: secretRef,
            isFavorite: draft.isFavorite,
            group: draft.groupID.flatMap { gid in groups.first { $0.id == gid } },
            tags: draft.tagIDs.compactMap { tid in tags.first { $0.id == tid } }
        )
        items.append(item)
        selectedItemID = item.id
        saveMetadata()
    }

    func updateItem(id: UUID, mutation: VaultItemMutation) async throws {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard let key = vaultKey else { return }
        if let title = mutation.title { item.title = title }
        if let website = mutation.website { item.website = website }
        if let username = mutation.username { item.username = username }
        if let email = mutation.email { item.email = email }
        if let phone = mutation.phone { item.phone = phone }
        if let notePreview = mutation.notePreview { item.notePreview = notePreview }
        if let groupID = mutation.groupID { item.group = groups.first { $0.id == groupID } }
        if let tagIDs = mutation.tagIDs { item.tags = tagIDs.compactMap { tid in tags.first { $0.id == tid } } }
        let passwordHistory: [PasswordHistoryEntry]
        do {
            let encryptedData = try loadSecretData(for: item.secretRef)
            let encrypted = try JSONDecoder().decode(EncryptedSecret.self, from: encryptedData)
            let oldPayload = try cryptoService.decrypt(encrypted, itemID: item.id, vaultKey: key)
            passwordHistory = oldPayload.passwordHistory + [PasswordHistoryEntry(timestamp: Date(), password: oldPayload.password)]
        } catch {
            passwordHistory = []
        }
        if let password = mutation.password {
            let payload = SecretPayload(password: password, passwordHistory: passwordHistory)
            let encrypted = try cryptoService.encrypt(payload, itemID: item.id, vaultKey: key)
            let encryptedData = try JSONEncoder().encode(encrypted)
            try storeSecretData(encryptedData, for: item.secretRef)
            item.passwordHistoryCount = passwordHistory.count
        }
        item.updatedAt = Date()
        saveMetadata()
    }

    func revealSecret(id: UUID, reason: String = "查看密码") async throws -> SecretPayload {
        try await authService.authenticate(reason: reason, scope: .viewSecret)
        guard let key = vaultKey else { throw AuthError.unavailable }
        guard let item = items.first(where: { $0.id == id }) else { throw AuthError.failed }
        item.lastUsedAt = Date(); saveMetadata()
        let encryptedData = try loadSecretData(for: item.secretRef)
        let encrypted = try JSONDecoder().decode(EncryptedSecret.self, from: encryptedData)
        return try cryptoService.decrypt(encrypted, itemID: item.id, vaultKey: key)
    }

    func copyPassword(id: UUID) async throws {
        let secret = try await revealSecret(id: id, reason: "复制密码")
        clipboardCleaner.copyToClipboard(secret.password)
    }

    func copyUsername(id: UUID) {
        guard let item = items.first(where: { $0.id == id }), let username = item.username else { return }
        item.lastUsedAt = Date(); saveMetadata()
        clipboardCleaner.copyToClipboard(username, clearAfter: 60)
    }

    func copyEmail(id: UUID) {
        guard let item = items.first(where: { $0.id == id }), let email = item.email else { return }
        item.lastUsedAt = Date(); saveMetadata()
        clipboardCleaner.copyToClipboard(email, clearAfter: 60)
    }

    func copyPhone(id: UUID) {
        guard let item = items.first(where: { $0.id == id }), let phone = item.phone else { return }
        item.lastUsedAt = Date(); saveMetadata()
        clipboardCleaner.copyToClipboard(phone, clearAfter: 60)
    }

    // MARK: - Trash

    func moveToTrash(ids: [UUID]) {
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            item.isDeleted = true; item.deletedAt = Date()
            if selectedItemID == id { selectedItemID = nil }
        }
        saveMetadata()
    }

    func restoreFromTrash(ids: [UUID]) {
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            item.isDeleted = false; item.deletedAt = nil
            if selectedItemID == id { selectedItemID = nil }
        }
        saveMetadata()
    }

    func permanentlyDelete(ids: [UUID]) async throws {
        try await authService.authenticate(reason: "永久删除密码条目", scope: .destructive)
        for id in ids {
            if let item = items.first(where: { $0.id == id }) {
                try? keychainStore.deleteSecret(for: item.secretRef)
                memorySecrets.removeValue(forKey: item.secretRef)
            }
        }
        items.removeAll { ids.contains($0.id) }
        if let sid = selectedItemID, ids.contains(sid) { selectedItemID = nil }
        saveMetadata()
    }

    func permanentlyDeleteWithoutAuth(ids: [UUID]) {
        for id in ids {
            if let item = items.first(where: { $0.id == id }) {
                try? keychainStore.deleteSecret(for: item.secretRef)
                memorySecrets.removeValue(forKey: item.secretRef)
            }
        }
        items.removeAll { ids.contains($0.id) }
        if let sid = selectedItemID, ids.contains(sid) { selectedItemID = nil }
        saveMetadata()
    }

    func toggleFavorite(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.isFavorite.toggle()
        saveMetadata()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        for (index, group) in groups.enumerated() { group.sortOrder = index }
        saveMetadata()
    }

    func moveTags(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        saveMetadata()
    }

    // MARK: - Groups & Tags

    func createGroup(name: String, colorHex: String? = nil, colorHexes: [String]? = nil) {
        let group = VaultGroup(name: name, colorHex: colorHex, colorHexes: colorHexes, sortOrder: groups.count)
        groups.append(group); saveMetadata()
    }
    func updateGroup(id: UUID, name: String? = nil, colorHex: String? = nil, colorHexes: [String]? = nil) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        if let name = name { group.name = name }
        if let colorHex = colorHex { group.colorHex = colorHex }
        if let colorHexes = colorHexes { group.colorHexes = colorHexes }
        group.updatedAt = Date(); saveMetadata()
    }
    func deleteGroup(id: UUID) { groups.removeAll { $0.id == id }; saveMetadata() }

    func createTag(name: String, colorHex: String? = nil, colorHexes: [String]? = nil) {
        let tag = VaultTag(name: name, colorHex: colorHex, colorHexes: colorHexes)
        tags.append(tag); saveMetadata()
    }
    func updateTag(id: UUID, name: String? = nil, colorHex: String? = nil, colorHexes: [String]? = nil) {
        guard let tag = tags.first(where: { $0.id == id }) else { return }
        if let name = name { tag.name = name }
        if let colorHex = colorHex { tag.colorHex = colorHex }
        if let colorHexes = colorHexes { tag.colorHexes = colorHexes }
        tag.updatedAt = Date(); saveMetadata()
    }
    func deleteTag(id: UUID) { tags.removeAll { $0.id == id }; saveMetadata() }

    // MARK: - Sample data

    func loadSampleData() async {
        guard let key = vaultKey else { return }
        let group1 = VaultGroup(name: "社交", colorHex: "#4A90D9", sortOrder: 0)
        let group2 = VaultGroup(name: "工作", colorHex: "#E67E22", sortOrder: 1)
        let group3 = VaultGroup(name: "金融", colorHex: "#2ECC71", sortOrder: 2)
        groups = [group1, group2, group3]
        let tag1 = VaultTag(name: "常用", colorHex: "#E74C3C")
        let tag2 = VaultTag(name: "重要", colorHex: "#F1C40F")
        let tag3 = VaultTag(name: "临时", colorHex: "#95A5A6")
        tags = [tag1, tag2, tag3]

        let sampleEntries: [(String, String, String, String, String, String, String, VaultGroup?, [VaultTag], Bool)] = [
            ("微信", "https://weixin.qq.com", "mywechat@example.com", "wechat@example.com", "13800001111", "WeChatP@ss123", "主微信号", group1, [tag1, tag2], false),
            ("微博", "https://weibo.com", "myweibo_user", "", "", "Weibo#2024!", "个人微博账号", group1, [tag1], false),
            ("公司邮箱", "https://mail.company.com", "zhangsan@company.com", "zhangsan@company.com", "", "C0mpanyM@il", "工作邮箱", group2, [tag2], false),
            ("企业微信", "https://work.weixin.qq.com", "zhangsan_work", "zhangsan@company.com", "", "WorkWX!567", "公司通讯", group2, [tag1, tag2], false),
            ("支付宝", "https://www.alipay.com", "payment@example.com", "payment@example.com", "13900002222", "AliP@y2024", "日常支付", group3, [tag1, tag2], false),
            ("招商银行", "https://www.cmbchina.com", "6225****1234", "", "", "CmbCh1na#", "工资卡", group3, [tag2], false),
            ("GitHub", "https://github.com", "mygithub", "dev@example.com", "", "GitHub!Dev99", "代码仓库", group2, [tag1], false),
            ("已删除的旧账号", "https://old-site.com", "olduser", "old@example.com", "", "OldP@ssword1", "旧账号", group3, [tag3], true),
        ]

        for (title, website, username, email, phone, password, note, group, itemTags, isDeleted) in sampleEntries {
            let secretRef = UUID().uuidString; let itemID = UUID()
            let payload = SecretPayload(password: password)
            if let encrypted = try? cryptoService.encrypt(payload, itemID: itemID, vaultKey: key),
               let encryptedData = try? JSONEncoder().encode(encrypted) {
                try? storeSecretData(encryptedData, for: secretRef)
            }
            let item = VaultItem(id: itemID, title: title, website: website, username: username,
                                 email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone,
                                 notePreview: note, secretRef: secretRef, isDeleted: isDeleted,
                                 deletedAt: isDeleted ? Date() : nil, group: group, tags: itemTags)
            items.append(item)
        }
    }

    func storeSecretData(_ data: Data, for secretRef: String) throws {
        memorySecrets[secretRef] = data
        try keychainStore.storeSecret(data, for: secretRef)
    }

    private func loadSecretData(for secretRef: String) throws -> Data {
        if let memData = memorySecrets[secretRef] { return memData }
        if let keychainData = try? keychainStore.loadSecret(for: secretRef) {
            memorySecrets[secretRef] = keychainData; return keychainData
        }
        throw KeychainError.itemNotFound
    }

    func appendItem(_ item: VaultItem) { items.append(item) }
    func appendGroup(_ group: VaultGroup) {
        if !groups.contains(where: { $0.id == group.id }) { groups.append(group) }
    }
    func appendTag(_ tag: VaultTag) {
        if !tags.contains(where: { $0.id == tag.id }) { tags.append(tag) }
    }

    // MARK: - Backup

    func exportBackup(password: String) async throws -> BackupRecord {
        try await authService.authenticate(reason: "导出加密备份", scope: .destructive)
        guard let key = vaultKey else { throw VaultError.notInitialized }
        var record = try BackupService.exportBackup(
            items: items, groups: groups, tags: tags, keychainStore: keychainStore
        )
        try BackupService.attachVaultKey(to: &record, vaultKey: key, password: password)
        return record
    }

    func tryImportBackupLocal(from url: URL) async throws -> Bool {
        let record = try BackupService.readBackup(from: url)
        if let recovered = BackupService.tryDecryptVaultKeyLocal(from: record, vaultKey: vaultKey) {
            self.vaultKey = recovered
            let keyData = recovered.withUnsafeBytes { Data($0) }
            try keychainStore.storeVaultKey(keyData)
            try await BackupService.importBackup(record, into: self)
            saveMetadata()
            return true
        }
        return false
    }

    func importBackup(from url: URL, password: String) async throws {
        try await authService.authenticate(reason: "导入加密备份", scope: .destructive)
        let record = try BackupService.readBackup(from: url)
        let recovered = try BackupService.decryptVaultKey(from: record, password: password)
        self.vaultKey = recovered
        isVaultReady = true
        let keyData = recovered.withUnsafeBytes { Data($0) }
        try keychainStore.storeVaultKey(keyData)
        try await BackupService.importBackup(record, into: self)
        saveMetadata()
    }

    // MARK: - CSV Import

    func importCSVItems(_ csvItems: [BackupService.CSVImportItem]) async throws {
        try await authService.authenticate(reason: "导入 CSV 数据", scope: .destructive)
        guard let key = vaultKey else { throw VaultError.notInitialized }

        var importedCount = 0
        for csvItem in csvItems {
            let group: VaultGroup? = csvItem.groupName.flatMap { name in
                if let existing = groups.first(where: { $0.name == name }) { return existing }
                let ng = VaultGroup(name: name, sortOrder: groups.count)
                groups.append(ng)
                return ng
            }

            let resolvedTags: [VaultTag] = csvItem.tagNames.compactMap { name in
                if let existing = tags.first(where: { $0.name == name }) { return existing }
                let nt = VaultTag(name: name)
                tags.append(nt)
                return nt
            }

            let password: String
            if let pwd = csvItem.password, !pwd.isEmpty, pwd != "[认证失败]" {
                password = pwd
            } else {
                password = PasswordGenerator.generate(options: PasswordGenerator.Options(
                    length: 20, includeUppercase: true, includeLowercase: true, includeDigits: true, includeSymbols: true
                ))
            }

            let secretRef = UUID().uuidString
            let itemID = UUID()
            let payload = SecretPayload(password: password)
            let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: key)
            let encryptedData = try JSONEncoder().encode(encrypted)
            try storeSecretData(encryptedData, for: secretRef)

            let item = VaultItem(
                id: itemID, title: csvItem.title, website: csvItem.website,
                username: csvItem.username, email: csvItem.email, phone: csvItem.phone,
                notePreview: csvItem.notePreview, secretRef: secretRef,
                group: group, tags: resolvedTags
            )
            self.items.append(item)
            importedCount += 1
        }
        if importedCount > 0 { saveMetadata() }
    }

    // MARK: - Lock / Unlock

    func lock() {
        isLocked = true
        memorySecrets.removeAll()
        if let auth = authService as? LAAuthService { auth.invalidateAllSessions() }
    }

    func unlock() async -> Bool {
        guard authService.canAuthenticate() else { isLocked = false; return true }
        do {
            try await authService.authenticate(reason: "解锁 PwdSafe", scope: .viewSecret)
            isLocked = false; return true
        } catch { return false }
    }

    // MARK: - Persistence

    private var dataDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PwdSafe")
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
        let dir = appSupport.appendingPathComponent("PwdSafe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var metadataURL: URL { dataDirectory.appendingPathComponent("vault_metadata.json") }
    private var hasPersistedData: Bool { FileManager.default.fileExists(atPath: metadataURL.path) }

    private func saveMetadata() {
        let persistedItems = items.map { item in
            PersistedItem(id: item.id, title: item.title, website: item.website, username: item.username,
                          email: item.email, phone: item.phone, notePreview: item.notePreview,
                          secretRef: item.secretRef, isFavorite: item.isFavorite, isDeleted: item.isDeleted,
                          deletedAt: item.deletedAt, createdAt: item.createdAt, updatedAt: item.updatedAt,
                          lastUsedAt: item.lastUsedAt, passwordHistoryCount: item.passwordHistoryCount,
                          groupID: item.group?.id, tagIDs: item.tags.map(\.id))
        }
        let persistedGroups = groups.map { group in
            PersistedGroup(id: group.id, name: group.name, colorHex: group.colorHex,
                           colorHexes: group.colorHexes, sortOrder: group.sortOrder,
                           createdAt: group.createdAt, updatedAt: group.updatedAt)
        }
        let persistedTags = tags.map { tag in
            PersistedTag(id: tag.id, name: tag.name, colorHex: tag.colorHex,
                         colorHexes: tag.colorHexes, createdAt: tag.createdAt, updatedAt: tag.updatedAt)
        }
        let data = PersistedVaultData(items: persistedItems, groups: persistedGroups, tags: persistedTags)
        if let encoded = try? JSONEncoder().encode(data) {
            do {
                try encoded.write(to: metadataURL, options: .atomic)
            } catch {
                Logger(subsystem: "com.pwdsafe.app", category: "persistence").error("failed to save metadata: \(error)")
            }
        }
        items = items
        groups = groups
        tags = tags
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let persisted = try? JSONDecoder().decode(PersistedVaultData.self, from: data) else { return }
        let loadedGroups = persisted.groups.map { pg in
            VaultGroup(id: pg.id, name: pg.name, colorHex: pg.colorHex, colorHexes: pg.colorHexes,
                       sortOrder: pg.sortOrder, createdAt: pg.createdAt, updatedAt: pg.updatedAt)
        }
        let loadedTags = persisted.tags.map { pt in
            VaultTag(id: pt.id, name: pt.name, colorHex: pt.colorHex, colorHexes: pt.colorHexes,
                     createdAt: pt.createdAt, updatedAt: pt.updatedAt)
        }
        let groupMap = Dictionary(uniqueKeysWithValues: loadedGroups.map { ($0.id, $0) })
        let tagMap = Dictionary(uniqueKeysWithValues: loadedTags.map { ($0.id, $0) })
        let loadedItems = persisted.items.map { pi in
            VaultItem(id: pi.id, title: pi.title, website: pi.website, username: pi.username,
                      email: pi.email, phone: pi.phone, notePreview: pi.notePreview,
                      secretRef: pi.secretRef, isFavorite: pi.isFavorite, isDeleted: pi.isDeleted,
                      deletedAt: pi.deletedAt, createdAt: pi.createdAt, updatedAt: pi.updatedAt,
                      lastUsedAt: pi.lastUsedAt, passwordHistoryCount: pi.passwordHistoryCount,
                      group: pi.groupID.flatMap { groupMap[$0] },
                      tags: pi.tagIDs.compactMap { tagMap[$0] })
        }
        groups = loadedGroups; tags = loadedTags; items = loadedItems
    }
}

struct VaultItemDraft: Sendable {
    var title: String; var website: String?; var username: String?; var email: String?
    var phone: String?; var password: String; var notePreview: String?
    var isFavorite: Bool = false; var groupID: UUID?; var tagIDs: [UUID]
}

struct VaultItemMutation: Sendable {
    var title: String?; var website: String?; var username: String?; var email: String?
    var phone: String?; var password: String?; var notePreview: String?
    var groupID: UUID?; var tagIDs: [UUID]?
}
