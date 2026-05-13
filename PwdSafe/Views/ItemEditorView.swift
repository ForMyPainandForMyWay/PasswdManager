import SwiftUI

struct ItemEditorView: View {
    let repository: VaultRepository
    let mode: EditorMode
    let startAsFavorite: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var website: String = ""
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var password: String = ""
    @State private var notePreview: String = ""
    @State private var selectedGroupID: UUID?
    @State private var selectedTagIDs: [UUID] = []
    @State private var isSaving: Bool = false
    @State private var showPasswordGenerator: Bool = false

    enum EditorMode {
        case create
        case edit(VaultItem)
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var navigationTitle: String {
        isEditing ? "编辑密码条目" : "新建密码条目"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    TextField("网址", text: $website)
                    TextField("用户名", text: $username)
                    TextField("邮箱地址", text: $email)
                    TextField("手机号", text: $phone)
                    HStack {
                        SecureField("密码", text: $password)
                        Button {
                            showPasswordGenerator = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                        }
                        .buttonStyle(.plain)
                        .help("生成随机密码")
                    }
                }

                Section("备注") {
                    TextField("备注摘要", text: $notePreview, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("分组") {
                    Picker("分组", selection: $selectedGroupID) {
                        Text("无分组").tag(nil as UUID?)
                        ForEach(repository.groups, id: \.id) { group in
                            Text(group.name).tag(group.id as UUID?)
                        }
                    }
                }

                Section("标签") {
                    ForEach(repository.tags, id: \.id) { tag in
                        TagRowView(
                            tag: tag,
                            isSelected: selectedTagIDs.contains(tag.id),
                            onToggle: { toggleTag(tag.id) }
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.isEmpty || isSaving)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 540, idealHeight: 600)
        .onAppear {
            if case .edit(let item) = mode {
                title = item.title
                website = item.website ?? ""
                username = item.username ?? ""
                email = item.email ?? ""
                phone = item.phone ?? ""
                password = ""
                notePreview = item.notePreview ?? ""
                selectedGroupID = item.group?.id
                selectedTagIDs = item.tags.map(\.id)
            }
        }
        .sheet(isPresented: $showPasswordGenerator) {
            PasswordGeneratorView(generatedPassword: $password)
        }
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.removeAll { $0 == id }
        } else {
            selectedTagIDs.append(id)
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                switch mode {
                case .create:
                    let draft = VaultItemDraft(
                        title: title,
                        website: website.isEmpty ? nil : website,
                        username: username.isEmpty ? nil : username,
                        email: email.isEmpty ? nil : email,
                        phone: phone.isEmpty ? nil : phone,
                        password: password,
                        notePreview: notePreview.isEmpty ? nil : notePreview,
                        isFavorite: startAsFavorite,
                        groupID: selectedGroupID,
                        tagIDs: selectedTagIDs
                    )
                    try await repository.createItem(draft)
                case .edit(let item):
                    let mutation = VaultItemMutation(
                        title: title,
                        website: website.isEmpty ? nil : website,
                        username: username.isEmpty ? nil : username,
                        email: email.isEmpty ? nil : email,
                        phone: phone.isEmpty ? nil : phone,
                        password: password.isEmpty ? nil : password,
                        notePreview: notePreview.isEmpty ? nil : notePreview,
                        groupID: selectedGroupID,
                        tagIDs: selectedTagIDs
                    )
                    try await repository.updateItem(id: item.id, mutation: mutation)
                }
                dismiss()
            } catch {
                isSaving = false
            }
        }
    }
}

private struct TagRowView: View {
    let tag: VaultTag
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        let tagColor: Color = Color(hex: tag.colorHex) ?? .secondary
        HStack {
            Image(systemName: "tag.fill")
                .foregroundStyle(tagColor)
            Text(tag.name)
                .foregroundStyle(tagColor)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}