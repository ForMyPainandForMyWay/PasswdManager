import SwiftUI

struct ItemListView: View {
    @Bindable var repository: VaultRepository
    let selectedNavigation: NavigationItem

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            listContent
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbar
        }
    }

    private var isTrashMode: Bool {
        if case .trash = selectedNavigation { return true }
        return false
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索标题、网址、用户名、分组、标签...", text: $repository.searchQuery)
                .textFieldStyle(.plain)
            if !repository.searchQuery.isEmpty {
                Button {
                    repository.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.bar)
    }

    private var listContent: some View {
        List(selection: Binding(
            get: { repository.selectedItemID },
            set: { repository.selectItem($0) }
        )) {
            ForEach(displayedItems) { item in
                ItemRowView(
                    item: item,
                    repository: repository,
                    isTrashMode: isTrashMode
                )
                    .tag(item.id)
                    .swipeActions(edge: .trailing) {
                        if isTrashMode {
                            Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await repository.permanentlyDelete(ids: [item.id])
                                        } catch AuthError.cancelled {
                                        }
                                    }
                                } label: {
                                    Label("永久删除", systemImage: "trash")
                                }
                        } else {
                            Button(role: .destructive) {
                                repository.moveToTrash(ids: [item.id])
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if isTrashMode {
                            Button {
                                repository.restoreFromTrash(ids: [item.id])
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private var displayedItems: [VaultItem] {
        switch selectedNavigation {
        case .allItems:
            return repository.filteredItems
        case .favorites:
            return repository.favoriteItems.filter { item in
                if repository.searchQuery.isEmpty { return true }
                return repository.filteredItems.contains(where: { $0.id == item.id })
            }
        case .trash:
            return repository.trashedItems
        case .group(let groupID):
            let groupItems = repository.items(for: repository.groups.first(where: { $0.id == groupID }) ?? VaultGroup(name: ""))
            if repository.searchQuery.isEmpty {
                return groupItems
            }
            return groupItems.filter { item in
                repository.filteredItems.contains(where: { $0.id == item.id })
            }
        case .tag(let tagID):
            let tagItems = repository.items(for: repository.tags.first(where: { $0.id == tagID }) ?? VaultTag(name: ""))
            if repository.searchQuery.isEmpty {
                return tagItems
            }
            return tagItems.filter { item in
                repository.filteredItems.contains(where: { $0.id == item.id })
            }
        }
    }

    private var bottomToolbar: some View {
        HStack {
            Spacer()
            Text("\(displayedItems.count) 个项目")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct ItemRowView: View {
    let item: VaultItem
    let repository: VaultRepository
    let isTrashMode: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isTrashMode ? "trash.fill" : (item.isFavorite ? "star.fill" : "key.fill"))
                .foregroundStyle(isTrashMode ? Color.secondary : (item.isFavorite ? Color.yellow : (Color(hex: item.group?.colorHex) ?? Color.secondary)))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let username = item.username, !username.isEmpty {
                        Text(username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let group = item.group {
                        Text("· \(group.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            if isTrashMode {
                Button {
                    repository.restoreFromTrash(ids: [item.id])
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
                Divider()
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await repository.permanentlyDelete(ids: [item.id])
                                        } catch AuthError.cancelled {
                                        }
                                    }
                                } label: {
                                    Label("永久删除", systemImage: "trash")
                                }
                            } else {
                Button {
                    repository.toggleFavorite(id: item.id)
                } label: {
                    Label(
                        item.isFavorite ? "取消收藏" : "收藏",
                        systemImage: item.isFavorite ? "star.slash" : "star"
                    )
                }
                Divider()
                Button(role: .destructive) {
                    repository.moveToTrash(ids: [item.id])
                } label: {
                    Label("移到回收站", systemImage: "trash")
                }
                Divider()
                Button(role: .destructive) {
                    Task {
                        do {
                            try await repository.permanentlyDelete(ids: [item.id])
                                        } catch AuthError.cancelled {
                                        }
                                    }
                                } label: {
                                    Label("永久删除", systemImage: "trash.fill")
                                }
                            }
        }
    }
}