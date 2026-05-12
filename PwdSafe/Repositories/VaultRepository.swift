import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class VaultRepository {
    private(set) var items: [VaultItem] = []
    private(set) var groups: [VaultGroup] = []
    private(set) var tags: [VaultTag] = []
    private(set) var selectedItemID: UUID?
    var searchQuery: String = ""
    var isEditorPresented: Bool = false
    var editingItem: VaultItem?
    var newItemStartAsFavorite: Bool = false

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

    func createItem(_ draft: VaultItemDraft) {
        let item = VaultItem(
            title: draft.title,
            website: draft.website,
            username: draft.username,
            notePreview: draft.notePreview,
            secretRef: UUID().uuidString,
            isFavorite: draft.isFavorite,
            group: draft.groupID.flatMap { gid in groups.first { $0.id == gid } },
            tags: draft.tagIDs.compactMap { tid in tags.first { $0.id == tid } }
        )
        items.append(item)
        selectedItemID = item.id
    }

    func updateItem(id: UUID, mutation: VaultItemMutation) {
        guard let item = items.first(where: { $0.id == id }) else { return }
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
        item.updatedAt = Date()
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

    func permanentlyDelete(ids: [UUID]) {
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

    func loadSampleData() {
        let group1 = VaultGroup(name: "社交", colorHex: "#4A90D9", sortOrder: 0)
        let group2 = VaultGroup(name: "工作", colorHex: "#E67E22", sortOrder: 1)
        let group3 = VaultGroup(name: "金融", colorHex: "#2ECC71", sortOrder: 2)
        groups = [group1, group2, group3]

        let tag1 = VaultTag(name: "常用", colorHex: "#E74C3C")
        let tag2 = VaultTag(name: "重要", colorHex: "#F1C40F")
        let tag3 = VaultTag(name: "临时", colorHex: "#95A5A6")
        tags = [tag1, tag2, tag3]

        items = [
            VaultItem(
                title: "微信",
                website: "https://weixin.qq.com",
                username: "mywechat@example.com",
                notePreview: "主微信号，用于日常通讯",
                secretRef: UUID().uuidString,
                group: group1,
                tags: [tag1, tag2]
            ),
            VaultItem(
                title: "微博",
                website: "https://weibo.com",
                username: "myweibo_user",
                notePreview: "个人微博账号",
                secretRef: UUID().uuidString,
                group: group1,
                tags: [tag1]
            ),
            VaultItem(
                title: "公司邮箱",
                website: "https://mail.company.com",
                username: "zhangsan@company.com",
                notePreview: "工作邮箱，每日检查",
                secretRef: UUID().uuidString,
                group: group2,
                tags: [tag2]
            ),
            VaultItem(
                title: "企业微信",
                website: "https://work.weixin.qq.com",
                username: "zhangsan_work",
                notePreview: "公司内部通讯工具",
                secretRef: UUID().uuidString,
                group: group2,
                tags: [tag1, tag2]
            ),
            VaultItem(
                title: "支付宝",
                website: "https://www.alipay.com",
                username: "payment@example.com",
                notePreview: "日常支付账户",
                secretRef: UUID().uuidString,
                group: group3,
                tags: [tag1, tag2]
            ),
            VaultItem(
                title: "招商银行",
                website: "https://www.cmbchina.com",
                username: "6225****1234",
                notePreview: "工资卡，主要储蓄账户",
                secretRef: UUID().uuidString,
                group: group3,
                tags: [tag2]
            ),
            VaultItem(
                title: "GitHub",
                website: "https://github.com",
                username: "mygithub",
                notePreview: "代码仓库，包含多个项目",
                secretRef: UUID().uuidString,
                group: group2,
                tags: [tag1]
            ),
            VaultItem(
                title: "已删除的旧账号",
                website: "https://old-site.com",
                username: "olduser",
                notePreview: "不再使用的旧账号",
                secretRef: UUID().uuidString,
                isDeleted: true,
                deletedAt: Date(),
                group: group3,
                tags: [tag3]
            ),
        ]
    }
}

struct VaultItemDraft: Sendable {
    var title: String
    var website: String?
    var username: String?
    var notePreview: String?
    var isFavorite: Bool = false
    var groupID: UUID?
    var tagIDs: [UUID]
}

struct VaultItemMutation: Sendable {
    var title: String? = nil
    var website: String? = nil
    var username: String? = nil
    var notePreview: String? = nil
    var groupID: UUID? = nil
    var tagIDs: [UUID]? = nil
}