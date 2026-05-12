import Testing
import Foundation
@testable import PwdSafe

@MainActor
struct VaultRepositoryTests {

    var repository: VaultRepository!

    init() {
        repository = VaultRepository()
        repository.loadSampleData()
    }

    @Test func testLoadSampleData() {
        #expect(repository.allItems.count == 7)
        #expect(repository.trashedItems.count == 1)
        #expect(repository.groups.count == 3)
        #expect(repository.tags.count == 3)
    }

    @Test func testAllItemsExcludesTrashed() {
        for item in repository.allItems {
            #expect(!item.isDeleted)
        }
    }

    @Test func testFavoriteItems() {
        let favorites = repository.favoriteItems
        #expect(favorites.allSatisfy { $0.isFavorite })
    }

    @Test func testTrashedItems() {
        let trashed = repository.trashedItems
        #expect(trashed.count == 1)
        #expect(trashed.first?.isDeleted == true)
    }

    @Test func testItemsForGroup() {
        let group = repository.groups.first!
        let items = repository.items(for: group)
        for item in items {
            #expect(item.group?.id == group.id)
            #expect(!item.isDeleted)
        }
    }

    @Test func testItemsForTag() {
        let tag = repository.tags.first!
        let items = repository.items(for: tag)
        for item in items {
            #expect(item.tags.contains(where: { $0.id == tag.id }))
            #expect(!item.isDeleted)
        }
    }

    @Test func testCreateItem() {
        let count = repository.allItems.count
        let draft = VaultItemDraft(
            title: "测试网站",
            website: "https://test.com",
            username: "testuser",
            notePreview: "测试备注",
            groupID: repository.groups.first?.id,
            tagIDs: [repository.tags.first!.id]
        )
        repository.createItem(draft)

        #expect(repository.allItems.count == count + 1)
        let newItem = repository.selectedItem()
        #expect(newItem != nil)
        #expect(newItem?.title == "测试网站")
        #expect(newItem?.website == "https://test.com")
        #expect(newItem?.username == "testuser")
        #expect(newItem?.notePreview == "测试备注")
        #expect(newItem?.group?.id == repository.groups.first?.id)
        #expect(newItem?.tags.contains(where: { $0.id == repository.tags.first!.id }) == true)
        #expect(newItem?.isDeleted == false)
        #expect(newItem?.isFavorite == false)
        #expect(!newItem!.secretRef.isEmpty)
    }

    @Test func testUpdateItem() {
        guard let item = repository.allItems.first else {
            #expect(Bool(false), "No items found")
            return
        }
        let originalTitle = item.title

        let mutation = VaultItemMutation(
            title: "更新后的标题",
            website: "https://updated.com",
            username: "updateduser",
            notePreview: "更新后的备注"
        )
        repository.updateItem(id: item.id, mutation: mutation)

        #expect(item.title == "更新后的标题")
        #expect(item.website == "https://updated.com")
        #expect(item.username == "updateduser")
        #expect(item.notePreview == "更新后的备注")
        #expect(item.title != originalTitle)
    }

    @Test func testMoveToTrash() {
        let item = repository.allItems.first!
        let itemID = item.id

        repository.moveToTrash(ids: [itemID])

        #expect(item.isDeleted == true)
        #expect(item.deletedAt != nil)
        #expect(repository.trashedItems.contains(where: { $0.id == itemID }))
        #expect(!repository.allItems.contains(where: { $0.id == itemID }))
    }

    @Test func testMoveToTrashClearsSelection() {
        let item = repository.allItems.first!
        repository.selectItem(item.id)
        #expect(repository.selectedItemID == item.id)

        repository.moveToTrash(ids: [item.id])

        #expect(repository.selectedItemID == nil)
    }

    @Test func testRestoreFromTrash() {
        let trashedItem = repository.trashedItems.first!
        let itemID = trashedItem.id

        repository.restoreFromTrash(ids: [itemID])

        #expect(trashedItem.isDeleted == false)
        #expect(trashedItem.deletedAt == nil)
        #expect(repository.allItems.contains(where: { $0.id == itemID }))
        #expect(!repository.trashedItems.contains(where: { $0.id == itemID }))
    }

    @Test func testPermanentlyDelete() {
        let trashedItem = repository.trashedItems.first!
        let itemID = trashedItem.id
        let trashedCount = repository.trashedItems.count

        repository.permanentlyDelete(ids: [itemID])

        #expect(repository.trashedItems.count == trashedCount - 1)
        #expect(!repository.items.contains(where: { $0.id == itemID }))
        #expect(!repository.allItems.contains(where: { $0.id == itemID }))
    }

    @Test func testPermanentlyDeleteClearsSelection() {
        let trashedItem = repository.trashedItems.first!
        repository.selectItem(trashedItem.id)

        repository.permanentlyDelete(ids: [trashedItem.id])

        #expect(repository.selectedItemID == nil)
    }

    @Test func testToggleFavorite() {
        let item = repository.allItems.first!
        let wasFavorite = item.isFavorite

        repository.toggleFavorite(id: item.id)
        #expect(item.isFavorite == !wasFavorite)

        repository.toggleFavorite(id: item.id)
        #expect(item.isFavorite == wasFavorite)
    }

    @Test func testSearchByTitle() {
        repository.searchQuery = "微信"
        let results = repository.filteredItems
        #expect(results.contains(where: { $0.title == "微信" }))
        #expect(!results.contains(where: { $0.title == "GitHub" }))
    }

    @Test func testSearchByWebsite() {
        repository.searchQuery = "github"
        let results = repository.filteredItems
        #expect(results.contains(where: { $0.title == "GitHub" }))
    }

    @Test func testSearchByUsername() {
        repository.searchQuery = "mygithub"
        let results = repository.filteredItems
        #expect(results.contains(where: { $0.title == "GitHub" }))
    }

    @Test func testSearchByNotePreview() {
        repository.searchQuery = "工资卡"
        let results = repository.filteredItems
        #expect(results.contains(where: { $0.title == "招商银行" }))
    }

    @Test func testSearchEmptyQuery() {
        repository.searchQuery = ""
        let results = repository.filteredItems
        #expect(results.count == repository.allItems.count)
    }

    @Test func testSearchNoMatch() {
        repository.searchQuery = "不存在的关键词xyz"
        let results = repository.filteredItems
        #expect(results.isEmpty)
    }

    @Test func testSearchIsCaseInsensitive() {
        repository.searchQuery = "GITHUB"
        let results = repository.filteredItems
        #expect(results.contains(where: { $0.title == "GitHub" }))
    }

    @Test func testSelectItem() {
        let item = repository.allItems.first!
        repository.selectItem(item.id)
        #expect(repository.selectedItemID == item.id)
        #expect(repository.selectedItem()?.id == item.id)
    }

    @Test func testDeselectItem() {
        repository.selectItem(nil)
        #expect(repository.selectedItemID == nil)
        #expect(repository.selectedItem() == nil)
    }

    @Test func testCreateGroup() {
        let count = repository.groups.count
        repository.createGroup(name: "新分组", colorHex: "#FF5733")
        #expect(repository.groups.count == count + 1)
        let newGroup = repository.groups.last!
        #expect(newGroup.name == "新分组")
        #expect(newGroup.colorHex == "#FF5733")
    }

    @Test func testUpdateGroup() {
        let group = repository.groups.first!
        let oldName = group.name
        repository.updateGroup(id: group.id, name: "改名分组", colorHex: "#000000")
        #expect(group.name == "改名分组")
        #expect(group.name != oldName)
        #expect(group.colorHex == "#000000")
    }

    @Test func testDeleteGroup() {
        let group = repository.groups.first!
        let groupID = group.id
        let count = repository.groups.count

        repository.deleteGroup(id: groupID)

        #expect(repository.groups.count == count - 1)
        #expect(!repository.groups.contains(where: { $0.id == groupID }))
    }

    @Test func testCreateTag() {
        let count = repository.tags.count
        repository.createTag(name: "新标签", colorHex: "#00FF00")
        #expect(repository.tags.count == count + 1)
        let newTag = repository.tags.last!
        #expect(newTag.name == "新标签")
        #expect(newTag.colorHex == "#00FF00")
    }

    @Test func testUpdateTag() {
        let tag = repository.tags.first!
        repository.updateTag(id: tag.id, name: "改名标签", colorHex: "#FFFFFF")
        #expect(tag.name == "改名标签")
        #expect(tag.colorHex == "#FFFFFF")
    }

    @Test func testDeleteTag() {
        let tag = repository.tags.first!
        let tagID = tag.id
        let count = repository.tags.count

        repository.deleteTag(id: tagID)

        #expect(repository.tags.count == count - 1)
        #expect(!repository.tags.contains(where: { $0.id == tagID }))
    }

    @Test func testUpdateItemGroup() {
        let item = repository.allItems.first!
        let newGroup = repository.groups.last!

        repository.updateItem(id: item.id, mutation: VaultItemMutation(groupID: newGroup.id))

        #expect(item.group?.id == newGroup.id)
    }

    @Test func testUpdateItemTags() {
        let item = repository.allItems.first!
        let newTags = [repository.tags.first!.id]

        repository.updateItem(id: item.id, mutation: VaultItemMutation(tagIDs: newTags))

        #expect(item.tags.count == 1)
        #expect(item.tags.first?.id == repository.tags.first!.id)
    }

    @Test func testBulkTrashOperations() {
        let items = Array(repository.allItems.prefix(2))
        let ids = items.map(\.id)

        repository.moveToTrash(ids: ids)

        for id in ids {
            #expect(!repository.allItems.contains(where: { $0.id == id }))
            #expect(repository.trashedItems.contains(where: { $0.id == id }))
        }
    }

    @Test func testBulkRestoreOperations() {
        let items = Array(repository.allItems.prefix(2))
        let ids = items.map(\.id)
        repository.moveToTrash(ids: ids)

        repository.restoreFromTrash(ids: ids)

        for id in ids {
            #expect(repository.allItems.contains(where: { $0.id == id }))
            #expect(!repository.trashedItems.contains(where: { $0.id == id }))
        }
    }

    @Test func testBulkPermanentDelete() {
        let items = Array(repository.allItems.prefix(2))
        let ids = items.map(\.id)
        repository.moveToTrash(ids: ids)

        repository.permanentlyDelete(ids: ids)

        for id in ids {
            #expect(!repository.items.contains(where: { $0.id == id }))
        }
    }
}