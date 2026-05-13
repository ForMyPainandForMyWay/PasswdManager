import SwiftUI
import UniformTypeIdentifiers

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
    static let pwdsafeBackup = UTType(exportedAs: "com.pwdsafe.backup", conformingTo: .json)
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

    private var isTrashMode: Bool {
        if case .trash = selectedNavigation { return true }
        return false
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
                            ToolbarItem {
                                if !isTrashMode, let item = repository.selectedItem(), !item.isDeleted {
                                    Button {
                                        repository.editingItem = item
                                        repository.isEditorPresented = true
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .help("编辑")
                                }
                            }
                            ToolbarItem {
                                if !isTrashMode {
                                    Button {
                                        repository.editingItem = nil
                                        repository.newItemStartAsFavorite = false
                                        repository.isEditorPresented = true
                                    } label: {
                                        Image(systemName: "plus.circle")
                                    }
                                    .help("新建密码条目")
                                }
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
                    defaultFilename: "PwdSafe_\(backupDateString()).pwdsafe-backup"
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

    private func prepareExport() async {
        isExporting = true
        do {
            let record = try await repository.exportBackup()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            backupDocument = BackupDocument(data: data)
            showExportPanel = true
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
        isExporting = false
    }
}