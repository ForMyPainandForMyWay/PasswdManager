import Foundation
import SwiftData
import Observation
import CryptoKit

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

    var allItems: [VaultItem] {
        items.filter { !$0.isDeleted }
    }

    var favoriteItems: [VaultItem] {
        allItems.filter { $0.isFavorite }
    }

    var trashedItems: [VaultItem] {
        items.filter { $0.isDeleted }
    }

    var filteredItems: [VaultItem] {
        if searchQuery.isEmpty {
            return allItems
        }
        let query = searchQuery.lowercased()
        return allItems.filter { item in
            item.title.lowercased().contains(query)
            || (item.website?.lowercased().contains(query) ?? false)
            || (item.username?.lowercased().contains(query) ?? false)
            || (item.notePreview?.lowercased().contains(query) ?? false)
        }
    }

    func items(for group: VaultGroup) -> [VaultItem] {
        allItems.filter { $0.group?.id == group.id }
    }

    func items(for tag: VaultTag) -> [VaultItem] {
        allItems.filter { $0.tags.contains(where: { $0.id == tag.id }) }
    }

    func selectItem(_ id: UUID?) {
        selectedItemID = id
    }

    func selectedItem() -> VaultItem? {
        guard let id = selectedItemID else { return nil }
        return items.first { $0.id == id }
    }

    func initializeVault() async throws {
        do {
            let keyData = try keychainStore.loadVaultKey()
            vaultKey = SymmetricKey(data: keyData)
            isVaultReady = true
        } catch KeychainError.itemNotFound {
            let key = try cryptoService.createVaultKey()
            try keychainStore.storeVaultKey(key.withUnsafeBytes { Data($0) })
            vaultKey = key
            isVaultReady = true
        }
    }

    func createItem(_ draft: VaultItemDraft) async throws {
        guard let key = vaultKey else { return }
        let secretRef = UUID().uuidString

        let payload = SecretPayload(
            password: draft.password,
            secureNote: nil,
            totpSeed: nil,
            customFields: []
        )
        let itemID = UUID()
        let encrypted = try cryptoService.encrypt(payload, itemID: itemID, vaultKey: key)
        let encryptedData = try JSONEncoder().encode(encrypted)
        try keychainStore.storeSecret(encryptedData, for: secretRef)

        let item = VaultItem(
            id: itemID,
            title: draft.title,
            website: draft.website,
            username: draft.username,
            notePreview: draft.notePreview,
            secretRef: secretRef,
            isFavorite: draft.isFavorite,
            group: draft.groupID.flatMap { gid in groups.first { $0.id == gid } },
            tags: draft.tagIDs.compactMap { tid in tags.first { $0.id == tid } }
        )
        items.append(item)
        selectedItemID = item.id
    }

    func updateItem(id: UUID, mutation: VaultItemMutation) async throws {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard let key = vaultKey else { return }

        if let title = mutation.title { item.title = title }
        if let website = mutation.website { item.website = website }
        if let username = mutation.username { item.username = username }
        if let notePreview = mutation.notePreview { item.notePreview = notePreview }
        if let groupID = mutation.groupID {
            item.group = groups.first { $0.id == groupID }
        }
        if let tagIDs = mutation.tagIDs {
            item.tags = tagIDs.compactMap { tid in tags.first { $0.id == tid } }
        }

        if let password = mutation.password {
            let payload = SecretPayload(
                password: password,
                secureNote: nil,
                totpSeed: nil,
                customFields: []
            )
            let encrypted = try cryptoService.encrypt(payload, itemID: item.id, vaultKey: key)
            let encryptedData = try JSONEncoder().encode(encrypted)
            try keychainStore.storeSecret(encryptedData, for: item.secretRef)
        }

        item.updatedAt = Date()
    }

    func revealSecret(id: UUID, reason: String = "查看密码") async throws -> SecretPayload {
        try await authService.authenticate(reason: reason)
        guard let key = vaultKey else { throw AuthError.unavailable }
        guard let item = items.first(where: { $0.id == id }) else { throw AuthError.failed }

        let encryptedData = try keychainStore.loadSecret(for: item.secretRef)
        let encrypted = try JSONDecoder().decode(EncryptedSecret.self, from: encryptedData)
        return try cryptoService.decrypt(encrypted, itemID: item.id, vaultKey: key)
    }

    func copyPassword(id: UUID) async throws {
        let secret = try await revealSecret(id: id, reason: "复制密码")
        clipboardCleaner.copyToClipboard(secret.password)
    }

    func copyUsername(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard let username = item.username else { return }
        clipboardCleaner.copyToClipboard(username, clearAfter: 60)
    }

    func moveToTrash(ids: [UUID]) {
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            item.isDeleted = true
            item.deletedAt = Date()
            if selectedItemID == id {
                selectedItemID = nil
            }
        }
    }

    func restoreFromTrash(ids: [UUID]) {
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            item.isDeleted = false
            item.deletedAt = nil
        }
    }

    func permanentlyDelete(ids: [UUID]) async throws {
        try await authService.authenticate(reason: "永久删除密码条目")

        for id in ids {
            if let item = items.first(where: { $0.id == id }) {
                try? keychainStore.deleteSecret(for: item.secretRef)
            }
        }
        items.removeAll { ids.contains($0.id) }
        if let sid = selectedItemID, ids.contains(sid) {
            selectedItemID = nil
        }
    }

    func permanentlyDeleteWithoutAuth(ids: [UUID]) {
        for id in ids {
            if let item = items.first(where: { $0.id == id }) {
                try? keychainStore.deleteSecret(for: item.secretRef)
            }
        }
        items.removeAll { ids.contains($0.id) }
        if let sid = selectedItemID, ids.contains(sid) {
            selectedItemID = nil
        }
    }

    func toggleFavorite(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.isFavorite.toggle()
    }

    func createGroup(name: String, colorHex: String? = nil) {
        let group = VaultGroup(name: name, colorHex: colorHex, sortOrder: groups.count)
        groups.append(group)
    }

    func updateGroup(id: UUID, name: String? = nil, colorHex: String? = nil) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        if let name = name { group.name = name }
        if let colorHex = colorHex { group.colorHex = colorHex }
        group.updatedAt = Date()
    }

    func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }

    func createTag(name: String, colorHex: String? = nil) {
        let tag = VaultTag(name: name, colorHex: colorHex)
        tags.append(tag)
    }

    func updateTag(id: UUID, name: String? = nil, colorHex: String? = nil) {
        guard let tag = tags.first(where: { $0.id == id }) else { return }
        if let name = name { tag.name = name }
        if let colorHex = colorHex { tag.colorHex = colorHex }
        tag.updatedAt = Date()
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
    }

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

        let sampleEntries: [(String, String, String, String, String, VaultGroup?, [VaultTag], Bool)] = [
            ("微信", "https://weixin.qq.com", "mywechat@example.com", "WeChatP@ss123", "主微信号，用于日常通讯", group1, [tag1, tag2], false),
            ("微博", "https://weibo.com", "myweibo_user", "Weibo#2024!", "个人微博账号", group1, [tag1], false),
            ("公司邮箱", "https://mail.company.com", "zhangsan@company.com", "C0mpanyM@il", "工作邮箱，每日检查", group2, [tag2], false),
            ("企业微信", "https://work.weixin.qq.com", "zhangsan_work", "WorkWX!567", "公司内部通讯工具", group2, [tag1, tag2], false),
            ("支付宝", "https://www.alipay.com", "payment@example.com", "AliP@y2024", "日常支付账户", group3, [tag1, tag2], false),
            ("招商银行", "https://www.cmbchina.com", "6225****1234", "CmbCh1na#", "工资卡，主要储蓄账户", group3, [tag2], false),
            ("GitHub", "https://github.com", "mygithub", "GitHub!Dev99", "代码仓库，包含多个项目", group2, [tag1], false),
            ("已删除的旧账号", "https://old-site.com", "olduser", "OldP@ssword1", "不再使用的旧账号", group3, [tag3], true),
        ]

        for (title, website, username, password, note, group, itemTags, isDeleted) in sampleEntries {
            let secretRef = UUID().uuidString
            let itemID = UUID()

            let payload = SecretPayload(
                password: password,
                secureNote: nil,
                totpSeed: nil,
                customFields: []
            )
            if let encrypted = try? cryptoService.encrypt(payload, itemID: itemID, vaultKey: key),
               let encryptedData = try? JSONEncoder().encode(encrypted) {
                try? keychainStore.storeSecret(encryptedData, for: secretRef)
            }

            let item = VaultItem(
                id: itemID,
                title: title,
                website: website,
                username: username,
                notePreview: note,
                secretRef: secretRef,
                isDeleted: isDeleted,
                deletedAt: isDeleted ? Date() : nil,
                group: group,
                tags: itemTags
            )
            items.append(item)
        }
    }

    func lock() {
        isLocked = true
        if let auth = authService as? LAAuthService {
            auth.invalidateSession()
        }
    }

    func unlock() async -> Bool {
        guard authService.canAuthenticate() else {
            isLocked = false
            return true
        }
        do {
            try await authService.authenticate(reason: "解锁 PwdSafe")
            isLocked = false
            return true
        } catch {
            return false
        }
    }
}

struct VaultItemDraft: Sendable {
    var title: String
    var website: String?
    var username: String?
    var password: String
    var notePreview: String?
    var isFavorite: Bool = false
    var groupID: UUID?
    var tagIDs: [UUID]
}

struct VaultItemMutation: Sendable {
    var title: String? = nil
    var website: String? = nil
    var username: String? = nil
    var password: String? = nil
    var notePreview: String? = nil
    var groupID: UUID? = nil
    var tagIDs: [UUID]? = nil
}