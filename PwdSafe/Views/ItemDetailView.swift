import SwiftUI

struct ItemDetailView: View {
    let repository: VaultRepository

    var body: some View {
        if let item = repository.selectedItem() {
            detailContent(for: item)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("选择一个密码条目")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("从左侧列表中选择一个条目查看详情")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailContent(for item: VaultItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(for: item)
                Divider()
                fieldSection(for: item)
                Divider()
                metadataSection(for: item)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            detailToolbar(for: item)
        }
        .toolbar {
            ToolbarItem {
                if !item.isDeleted {
                    Button {
                        repository.editingItem = item
                        repository.isEditorPresented = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("编辑")
                }
            }
        }
    }

    private func headerSection(for item: VaultItem) -> some View {
        HStack(spacing: 16) {
            Image(systemName: item.isFavorite ? "star.fill" : "key.fill")
                .font(.largeTitle)
                .foregroundStyle(item.isFavorite ? .yellow : .accentColor)
                .frame(width: 56, height: 56)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title)
                    .fontWeight(.semibold)
                if let website = item.website, !website.isEmpty {
                    Text(website)
                        .font(.body)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            Button {
                repository.toggleFavorite(id: item.id)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isFavorite ? "取消收藏" : "收藏")
        }
    }

    private func fieldSection(for item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let username = item.username, !username.isEmpty {
                detailFieldRow(label: "用户名", value: username, systemImage: "person.fill") {
                    copyToClipboard(username, label: "用户名")
                }
            }

            detailFieldRow(label: "密码", value: "••••••••", systemImage: "lock.fill") {
                copyToClipboard("[密码]", label: "密码")
            }

            if let notePreview = item.notePreview, !notePreview.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("备注", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(notePreview)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !item.tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("标签", systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(item.tags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    (Color(hex: tag.colorHex) ?? .secondary).opacity(0.15),
                                    in: Capsule()
                                )
                                .foregroundStyle(Color(hex: tag.colorHex) ?? .secondary)
                        }
                    }
                }
            }
        }
    }

    private func metadataSection(for item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("条目信息", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let group = item.group {
                HStack {
                    Text("分组")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(group.name, systemImage: "folder.fill")
                        .foregroundStyle(Color(hex: group.colorHex) ?? .accentColor)
                }
                .font(.callout)
            }

            HStack {
                Text("创建时间")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.createdAt, style: .date)
            }
            .font(.callout)

            HStack {
                Text("更新时间")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.updatedAt, style: .date)
            }
            .font(.callout)
        }
    }

    private func detailFieldRow(label: String, value: String, systemImage: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.body.monospaced())
                    .lineLimit(1)
                Spacer()
                Button {
                    action()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .help("复制\(label)")
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func detailToolbar(for item: VaultItem) -> some View {
        HStack {
            if item.isDeleted {
                Button(role: .destructive) {
                    repository.permanentlyDelete(ids: [item.id])
                } label: {
                    Label("永久删除", systemImage: "trash.slash")
                        .labelStyle(.iconOnly)
                }
                .help("永久删除")
            } else {
                Button(role: .destructive) {
                    repository.moveToTrash(ids: [item.id])
                } label: {
                    Label("移到回收站", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("移到回收站")
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func copyToClipboard(_ text: String, label: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}