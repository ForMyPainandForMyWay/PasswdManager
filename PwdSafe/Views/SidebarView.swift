import SwiftUI

struct SidebarView: View {
    let repository: VaultRepository
    @Binding var selectedNavigation: NavigationItem
    @State private var showGroupSheet: Bool = false
    @State private var showTagSheet: Bool = false

    var body: some View {
        List(selection: $selectedNavigation) {
            Section {
                ForEach(systemItems, id: \.id) { item in
                    NavigationLink(value: item) {
                        Label(item.title, systemImage: item.iconName)
                    }
                }
            }

            Section("分组") {
                ForEach(repository.groups) { group in
                    NavigationLink(value: NavigationItem.group(group.id)) {
                        Label(group.name, systemImage: "folder.fill")
                            .foregroundStyle(Color(hex: group.colorHex) ?? .accentColor)
                    }
                    .contextMenu {
                        Button("重命名") {}
                        Button("删除", role: .destructive) {
                            repository.deleteGroup(id: group.id)
                        }
                    }
                }
                Button {
                    showGroupSheet = true
                } label: {
                    Label("新建分组", systemImage: "plus")
                }
            }

            Section("标签") {
                ForEach(repository.tags) { tag in
                    NavigationLink(value: NavigationItem.tag(tag.id)) {
                        Label(tag.name, systemImage: "tag.fill")
                            .foregroundStyle(Color(hex: tag.colorHex) ?? .secondary)
                    }
                    .contextMenu {
                        Button("重命名") {}
                        Button("删除", role: .destructive) {
                            repository.deleteTag(id: tag.id)
                        }
                    }
                }
                Button {
                    showTagSheet = true
                } label: {
                    Label("新建标签", systemImage: "plus")
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showGroupSheet) {
            CreateGroupSheet(repository: repository, isPresented: $showGroupSheet)
        }
        .sheet(isPresented: $showTagSheet) {
            CreateTagSheet(repository: repository, isPresented: $showTagSheet)
        }
    }

    private var systemItems: [NavigationItem] {
        [.allItems, .favorites, .trash]
    }
}

private struct CreateGroupSheet: View {
    let repository: VaultRepository
    @Binding var isPresented: Bool
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $name)
            }
            .formStyle(.grouped)
            .navigationTitle("新建分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        guard !name.isEmpty else { return }
                        repository.createGroup(name: name)
                        isPresented = false
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 360, height: 140)
    }
}

private struct CreateTagSheet: View {
    let repository: VaultRepository
    @Binding var isPresented: Bool
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("标签名称", text: $name)
            }
            .formStyle(.grouped)
            .navigationTitle("新建标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        guard !name.isEmpty else { return }
                        repository.createTag(name: name)
                        isPresented = false
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 360, height: 140)
    }
}