import SwiftUI

struct ItemDetailView: View {
    let repository: VaultRepository

    @State private var revealedPassword: String?
    @State private var isRevealing: Bool = false
    @State private var revealError: String?

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
        .onChange(of: item.id) { _, _ in
            revealedPassword = nil
            revealError = nil
        }
    }

    private func headerSection(for item: VaultItem) -> some View {
        HStack(spacing: 16) {
            Image(systemName: item.isDeleted ? "trash.fill" : (item.isFavorite ? "star.fill" : "key.fill"))
                .font(.largeTitle)
                .foregroundStyle(item.isDeleted ? Color.secondary : (item.isFavorite ? Color.yellow : Color.accentColor))
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

            if !item.isDeleted {
                Button {
                    repository.toggleFavorite(id: item.id)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "取消收藏" : "收藏")
            }
        }
    }

    private func fieldSection(for item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let username = item.username, !username.isEmpty {
                detailFieldRow(label: "用户名", value: username, systemImage: "person.fill") {
                    repository.copyUsername(id: item.id)
                }
            }

            if let email = item.email, !email.isEmpty {
                detailFieldRow(label: "邮箱", value: email, systemImage: "envelope") {
                    repository.copyEmail(id: item.id)
                }
            }

            if let phone = item.phone, !phone.isEmpty {
                detailFieldRow(label: "手机", value: phone, systemImage: "phone") {
                    repository.copyPhone(id: item.id)
                }
            }

            if item.isDeleted {
                detailFieldRow(label: "密码", value: "已删除", systemImage: "lock.fill") {}
            } else if let revealed = revealedPassword {
                detailFieldRow(label: "密码", value: revealed, systemImage: "lock.open.fill") {
                    Task { await copyPassword(item) }
                }
            } else {
                HStack {
                    Label("密码", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await revealPassword(item) }
                    } label: {
                        HStack(spacing: 4) {
                            if isRevealing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "eye")
                            }
                            Text("点击查看")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRevealing)

                    if let error = revealError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
                    Task { await deleteFromTrash(item) }
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

    private func revealPassword(_ item: VaultItem) async {
        isRevealing = true
        revealError = nil
        do {
            let secret = try await repository.revealSecret(id: item.id)
            revealedPassword = secret.password
        } catch let error as AuthError {
            if case .cancelled = error {
                revealError = nil
            } else {
                revealError = "认证失败"
            }
        } catch {
            revealError = "无法解密: \(error.localizedDescription)"
        }
        isRevealing = false
    }

    private func copyPassword(_ item: VaultItem) async {
        do {
            try await repository.copyPassword(id: item.id)
        } catch {}
    }

    private func deleteFromTrash(_ item: VaultItem) async {
        do {
            try await repository.permanentlyDelete(ids: [item.id])
        } catch AuthError.cancelled {
        } catch {
            repository.permanentlyDeleteWithoutAuth(ids: [item.id])
        }
    }
}