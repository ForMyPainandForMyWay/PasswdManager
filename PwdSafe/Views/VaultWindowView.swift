import SwiftUI

enum NavigationItem: Hashable, Identifiable {
    case allItems
    case favorites
    case trash
    case group(UUID)
    case tag(UUID)

    var id: String {
        switch self {
        case .allItems: return "allItems"
        case .favorites: return "favorites"
        case .trash: return "trash"
        case .group(let id): return "group-\(id.uuidString)"
        case .tag(let id): return "tag-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .allItems: return "全部项目"
        case .favorites: return "收藏"
        case .trash: return "回收站"
        case .group: return "分组"
        case .tag: return "标签"
        }
    }

    var iconName: String {
        switch self {
        case .allItems: return "key.fill"
        case .favorites: return "star.fill"
        case .trash: return "trash.fill"
        case .group: return "folder.fill"
        case .tag: return "tag.fill"
        }
    }
}

struct VaultWindowView: View {
    @State private var repository = VaultRepository()
    @State private var selectedNavigation: NavigationItem = .allItems
    @State private var isInitializing: Bool = true

    var body: some View {
        Group {
            if isInitializing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在初始化保险库...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 960, height: 640)
            } else {
                NavigationSplitView {
                    SidebarView(
                        repository: repository,
                        selectedNavigation: $selectedNavigation
                    )
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
                } content: {
                    ItemListView(
                        repository: repository,
                        selectedNavigation: selectedNavigation
                    )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 500)
                } detail: {
                    ItemDetailView(repository: repository)
                }
                .sheet(isPresented: $repository.isEditorPresented) {
                    if let item = repository.editingItem {
                        ItemEditorView(repository: repository, mode: .edit(item), startAsFavorite: false)
                    } else {
                        ItemEditorView(repository: repository, mode: .create, startAsFavorite: repository.newItemStartAsFavorite)
                    }
                }
            }
        }
        .task {
            do {
                try await repository.initializeVault()
                await repository.loadSampleData()
                isInitializing = false
            } catch {
                isInitializing = false
            }
        }
    }
}