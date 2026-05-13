import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication

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

extension UTType {
    static let pwdsafeBackup = UTType(exportedAs: "com.pwdsafe.pwd", conformingTo: .json)
}

final class BackupDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.pwdsafeBackup] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.readFailed
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private func backupDateString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return formatter.string(from: Date())
}

struct VaultWindowView: View {
    @State private var repository = VaultRepository()
    @State private var selectedNavigation: NavigationItem = .allItems
    @State private var isInitializing: Bool = true
    @State private var showSettings: Bool = false
    @State private var showExportPanel: Bool = false
    @State private var showImportPanel: Bool = false
    @State private var exportError: String?
    @State private var importError: String?
    @State private var showExportError: Bool = false
    @State private var showImportError: Bool = false
    @State private var backupDocument: BackupDocument?
    @State private var isExporting: Bool = false
    @State private var showEmptyTrashConfirmation: Bool = false
    @State private var showMoveAllToTrashConfirmation: Bool = false
    @State private var lastActiveDate: Date = .distantPast
    @State private var authErrorMessage: String?
    @State private var authContext: LAContext = LAContext()
    @State private var authAttemptID: UUID = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("autoLockTimeout") private var autoLockTimeout: Int = AutoLockTimeout.minute5.rawValue

    private var autoLockSeconds: TimeInterval {
        TimeInterval(autoLockTimeout * 60)
    }

    private var isTrashMode: Bool {
        if case .trash = selectedNavigation { return true }
        return false
    }

    private var displayedItemIDs: [UUID] {
        switch selectedNavigation {
        case .allItems:
            return repository.filteredItems.map(\.id)
        case .favorites:
            return repository.favoriteItems.filter { item in
                repository.searchQuery.isEmpty || repository.filteredItems.contains(where: { $0.id == item.id })
            }.map(\.id)
        case .trash:
            return []
        case .group(let groupID):
            guard let group = repository.groups.first(where: { $0.id == groupID }) else { return [] }
            let items = repository.items(for: group)
            if repository.searchQuery.isEmpty { return items.map(\.id) }
            return items.filter { item in repository.filteredItems.contains(where: { $0.id == item.id }) }.map(\.id)
        case .tag(let tagID):
            guard let tag = repository.tags.first(where: { $0.id == tagID }) else { return [] }
            let items = repository.items(for: tag)
            if repository.searchQuery.isEmpty { return items.map(\.id) }
            return items.filter { item in repository.filteredItems.contains(where: { $0.id == item.id }) }.map(\.id)
        }
    }

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
            } else if repository.isLocked {
                lockScreen
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
                        .toolbar {
                            ToolbarItem {
                                if !isTrashMode {
                                    Button {
                                        repository.editingItem = nil
                                        repository.newItemStartAsFavorite = false
                                        repository.isEditorPresented = true
                                    } label: {
                                        Image(systemName: "plus")
                                    }
                                    .help("新建密码条目")
                                }
                            }
                            ToolbarItem {
                                if !isTrashMode, let item = repository.selectedItem(), !item.isDeleted {
                                    Button {
                                        Task { await editItem(item) }
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .help("编辑")
                                }
                            }
                            ToolbarItem {
                                if isTrashMode, let item = repository.selectedItem() {
                                    Button {
                                        repository.restoreFromTrash(ids: [item.id])
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .help("恢复")
                                }
                            }
                            ToolbarItem {
                                if isTrashMode, let item = repository.selectedItem() {
                                    Button(role: .destructive) {
                                        Task { await deleteFromTrash(item) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .help("永久删除")
                                }
                            }
                            ToolbarItem {
                                if isTrashMode {
                                    Button(role: .destructive) {
                                        showEmptyTrashConfirmation = true
                                    } label: {
                                        Image(systemName: "xmark.bin")
                                    }
                                    .help("清空回收站")
                                } else if let item = repository.selectedItem(), !item.isDeleted {
                                    Button(role: .destructive) {
                                        repository.moveToTrash(ids: [item.id])
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .help("移到回收站")
                                }
                            }
                            ToolbarItem {
                                if !isTrashMode {
                                    Button(role: .destructive) {
                                        showMoveAllToTrashConfirmation = true
                                    } label: {
                                        Image(systemName: "xmark.bin")
                                    }
                                    .help("清空条目到回收站")
                                }
                            }
                            ToolbarItem {
                                Menu {
                                    Button {
                                        Task { await prepareExport() }
                                    } label: {
                                        Label("导出加密备份...", systemImage: "square.and.arrow.up")
                                    }
                                    .disabled(isExporting)
                                    Button {
                                        showImportPanel = true
                                    } label: {
                                        Label("导入加密备份...", systemImage: "square.and.arrow.down")
                                    }
                                    Divider()
                                    Button {
                                        showSettings = true
                                    } label: {
                                        Label("设置...", systemImage: "gear")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuIndicator(.hidden)
                                .help("更多操作")
                            }
                        }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $repository.isEditorPresented) {
                    if let item = repository.editingItem {
                        ItemEditorView(repository: repository, mode: .edit(item), startAsFavorite: false)
                    } else {
                        ItemEditorView(repository: repository, mode: .create, startAsFavorite: repository.newItemStartAsFavorite)
                    }
                }
                .fileExporter(
                    isPresented: $showExportPanel,
                    document: backupDocument ?? BackupDocument(data: Data()),
                    contentType: .pwdsafeBackup,
                    defaultFilename: "PwdSafe_\(backupDateString()).pwd"
                ) { result in
                    if case .failure(let error) = result {
                        exportError = error.localizedDescription
                        showExportError = true
                    }
                    backupDocument = nil
                }
                .fileImporter(
                    isPresented: $showImportPanel,
                    allowedContentTypes: [.pwdsafeBackup],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        Task {
                            do {
                                try await repository.importBackup(from: url)
                            } catch AuthError.cancelled {
                            } catch {
                                importError = error.localizedDescription
                                showImportError = true
                            }
                        }
                    case .failure(let error):
                        importError = error.localizedDescription
                        showImportError = true
                    }
                }
                .alert("导出失败", isPresented: $showExportError) {
                    Button("确定", role: .cancel) {}
                } message: {
                    Text(exportError ?? "未知错误")
                }
                .alert("导入失败", isPresented: $showImportError) {
                    Button("确定", role: .cancel) {}
                } message: {
                    Text(importError ?? "未知错误")
                }
                .confirmationDialog(
                    "清空回收站",
                    isPresented: $showEmptyTrashConfirmation
                ) {
                    Button("清空回收站", role: .destructive) {
                        Task {
                            let allIDs = repository.trashedItems.map(\.id)
                            do {
                                try await repository.permanentlyDelete(ids: allIDs)
                            } catch AuthError.cancelled {
                            } catch {
                                repository.permanentlyDeleteWithoutAuth(ids: allIDs)
                            }
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("回收站中的所有项目将被永久删除，此操作不可撤销。")
                }
                .confirmationDialog(
                    "清空条目到回收站",
                    isPresented: $showMoveAllToTrashConfirmation
                ) {
                    Button("移入回收站", role: .destructive) {
                        let ids = displayedItemIDs
                        guard !ids.isEmpty else { return }
                        repository.moveToTrash(ids: ids)
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("当前列表中的 \(displayedItemIDs.count) 个密码条目将被移入回收站。")
                }
            }
        }
        .onChange(of: selectedNavigation) { _, _ in
            repository.selectItem(nil)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !repository.isLocked {
                let now = Date()
                if autoLockTimeout > 0 && now.timeIntervalSince(lastActiveDate) > autoLockSeconds {
                    repository.lock()
                }
            } else if newPhase == .background || newPhase == .inactive {
                lastActiveDate = Date()
            }
        }
        .task {
            do {
                try await repository.initializeVault()
                await repository.loadOrCreateSampleData()
                isInitializing = false
            } catch {
                isInitializing = false
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("PwdSafe 已锁定")
                .font(.title2)
                .fontWeight(.semibold)
            Text("需要认证以解锁保险库")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                Task { await unlockVault() }
            } label: {
                Text("点击解锁")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: 960, height: 640)
    }

    private func unlockVault() async {
        if await repository.unlock() {
            lastActiveDate = Date()
        }
    }

    private func deleteFromTrash(_ item: VaultItem) async {
        do {
            try await repository.permanentlyDelete(ids: [item.id])
        } catch AuthError.cancelled {
        } catch {
            repository.permanentlyDeleteWithoutAuth(ids: [item.id])
        }
    }

    private func editItem(_ item: VaultItem) async {
        if await repository.unlock() {
            repository.editingItem = item
            repository.isEditorPresented = true
        }
    }

    private func prepareExport() async {
        isExporting = true
        do {
            let record = try await repository.exportBackup()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            backupDocument = BackupDocument(data: data)
            showExportPanel = true
        } catch AuthError.cancelled {
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
        isExporting = false
    }
}
