import SwiftUI

struct ItemDetailView: View {
    let repository: VaultRepository

    @State private var revealedPassword: String?
    @State private var revealedSecret: SecretPayload?
    @State private var isRevealing: Bool = false
    @State private var revealError: String?
    @State private var copiedField: String?
    @State private var hoveredField: String?
    @State private var revealedHistoryIndices: Set<Int> = []
    @State private var isRevealingHistory: Bool = false
    @State private var enlargedText: String?
    @State private var showEnlarged: Bool = false

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
                passwordHistorySection
                Divider()
                metadataSection(for: item)
            }
            .padding(24)
        }
        .onChange(of: item.id) { _, _ in
            revealedPassword = nil
            revealedSecret = nil
            revealError = nil
            revealedHistoryIndices = []
        }
        .onChange(of: item.updatedAt) { _, _ in
            if revealedSecret != nil, let currentItem = repository.selectedItem(), currentItem.id == item.id {
                Task {
                    do {
                        let secret = try await repository.revealSecret(id: item.id)
                        revealedPassword = secret.password
                        revealedSecret = secret
                        revealedHistoryIndices = []
                    } catch { }
                }
            }
        }
        .sheet(isPresented: $showEnlarged) {
            if let text = enlargedText {
                VStack(spacing: 16) {
                    ScrollView {
                        Text(text)
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Spacer()
                        Button("关闭") { showEnlarged = false }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
                .frame(width: 480, height: 320)
            }
        }
    }

    private func headerSection(for item: VaultItem) -> some View {
        HStack(spacing: 16) {
            Image(systemName: item.isDeleted ? "trash.fill" : (item.isFavorite ? "star.fill" : "key.fill"))
                .font(.largeTitle)
                .foregroundStyle(item.isDeleted ? Color.secondary : (item.isFavorite ? Color.yellow : (Color(hex: item.group?.colorHex) ?? Color.secondary)))
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
        VStack(spacing: 0) {
            if let username = item.username, !username.isEmpty {
                interactiveFieldRow(icon: "person.fill", label: "用户名", value: username, fieldKey: "username") {
                    repository.copyUsername(id: item.id)
                }
            }

            if let email = item.email, !email.isEmpty {
                if hasPreviousField(item, before: "email") { Divider().padding(.vertical, 8) }
                interactiveFieldRow(icon: "envelope", label: "邮箱", value: email, fieldKey: "email") {
                    repository.copyEmail(id: item.id)
                }
            }

            if let phone = item.phone, !phone.isEmpty {
                if hasPreviousField(item, before: "phone") { Divider().padding(.vertical, 8) }
                interactiveFieldRow(icon: "phone", label: "手机", value: phone, fieldKey: "phone") {
                    repository.copyPhone(id: item.id)
                }
            }

            if hasPreviousField(item, before: "password") { Divider().padding(.vertical, 8) }

            if item.isDeleted {
                interactiveFieldRow(icon: "lock.fill", label: "密码", value: "已删除", fieldKey: "password_deleted") {}
            } else if let revealed = revealedPassword {
                interactiveFieldRow(icon: "lock.open.fill", label: "密码", value: revealed, fieldKey: "password") {
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
            }

            if let notePreview = item.notePreview, !notePreview.isEmpty {
                Divider().padding(.vertical, 8)
                HStack(spacing: 8) {
                    Label("备注", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(notePreview)
                        .font(.body)
                        .lineLimit(2)
                }
            }

            if !item.tags.isEmpty {
                Divider().padding(.vertical, 8)
                HStack(spacing: 8) {
                    Label("标签", systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
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
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            if !hovering {
                revealedPassword = nil
            }
        }
    }

    private func interactiveFieldRow(icon: String, label: String, value: String, fieldKey: String, copyAction: @escaping () -> Void) -> some View {
        let isCopied = copiedField == fieldKey
        let isHovered = hoveredField == fieldKey

        return HStack(spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            ZStack {
                Text(value)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .opacity(isCopied ? 0 : 1)
                    .scaleEffect(isCopied ? 0.8 : 1.0)
                Text("已拷贝")
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .opacity(isCopied ? 1 : 0)
                    .scaleEffect(isCopied ? 1.0 : 0.8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isHovered ? Color.secondary.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .animation(.easeInOut(duration: 0.25), value: isCopied)
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering in
                hoveredField = hovering ? fieldKey : nil
            }
            .onTapGesture {
                copyAction()
                copiedField = fieldKey
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if copiedField == fieldKey {
                        copiedField = nil
                    }
                }
            }
            .contextMenu {
                Button {
                    copyAction()
                    copiedField = fieldKey
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if copiedField == fieldKey {
                            copiedField = nil
                        }
                    }
                } label: {
                    Label("复制内容", systemImage: "doc.on.doc")
                }
                Button {
                    enlargedText = value
                    showEnlarged = true
                } label: {
                    Label("放大显示", systemImage: "text.magnifyingglass")
                }
            }
            Button {
                copyAction()
                copiedField = fieldKey
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if copiedField == fieldKey {
                        copiedField = nil
                    }
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help("复制\(label)")
        }
    }

    private func hasPreviousField(_ item: VaultItem, before field: String) -> Bool {
        switch field {
        case "email":
            return (item.username?.isEmpty == false)
        case "phone":
            return (item.username?.isEmpty == false) || (item.email?.isEmpty == false)
        case "password":
            return (item.username?.isEmpty == false) || (item.email?.isEmpty == false) || (item.phone?.isEmpty == false)
        default:
            return false
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

            if let lastUsed = item.lastUsedAt {
                HStack {
                    Text("上次使用")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastUsed, formatter: ItemDetailView.lastUsedDateFormatter)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var passwordHistorySection: some View {
        if let secret = revealedSecret, !secret.passwordHistory.isEmpty {
            let sortedHistory = secret.passwordHistory.sorted { $0.timestamp > $1.timestamp }
            VStack(spacing: 0) {
                Label("密码历史记录", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                ForEach(Array(sortedHistory.enumerated()), id: \.offset) { index, entry in
                    let fieldKey = "history_\(index)"
                    let isCopied = copiedField == fieldKey
                    let isHovered = hoveredField == fieldKey
                    let isRevealed = revealedHistoryIndices.contains(index)

                    if index > 0 {
                        Divider()
                            .padding(.vertical, 4)
                    }
                    HStack {
                        Text(entry.timestamp, formatter: ItemDetailView.historyDateFormatter)
                            .font(.body)
                        Spacer()
                        if isRevealed {
                            interactiveHistoryPassword(
                                password: entry.password, fieldKey: fieldKey,
                                isCopied: isCopied, isHovered: isHovered
                            )
                        } else {
                            Button {
                                Task { await revealHistoryPassword(at: index) }
                            } label: {
                                HStack(spacing: 4) {
                                    if isRevealingHistory {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "eye")
                                    }
                                    Text("点击查看")
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRevealingHistory)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func interactiveHistoryPassword(password: String, fieldKey: String, isCopied: Bool, isHovered: Bool) -> some View {
        Group {
            ZStack {
                Text(password)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .opacity(isCopied ? 0 : 1)
                    .scaleEffect(isCopied ? 0.8 : 1.0)
                Text("已拷贝")
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .opacity(isCopied ? 1 : 0)
                    .scaleEffect(isCopied ? 1.0 : 0.8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isHovered ? Color.secondary.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .animation(.easeInOut(duration: 0.25), value: isCopied)
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering in
                hoveredField = hovering ? fieldKey : nil
            }
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(password, forType: .string)
                copiedField = fieldKey
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if copiedField == fieldKey { copiedField = nil }
                }
            }
            .contextMenu {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(password, forType: .string)
                    copiedField = fieldKey
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if copiedField == fieldKey { copiedField = nil }
                    }
                } label: {
                    Label("复制密码", systemImage: "doc.on.doc")
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(password, forType: .string)
                copiedField = fieldKey
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if copiedField == fieldKey { copiedField = nil }
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help("复制密码")
        }
    }

    private func revealHistoryPassword(at index: Int) async {
        isRevealingHistory = true
        guard let item = repository.selectedItem() else {
            isRevealingHistory = false
            return
        }
        do {
            let secret = try await repository.revealSecret(id: item.id, reason: "查看历史密码")
            if index < secret.passwordHistory.count {
                revealedHistoryIndices.insert(index)
            }
        } catch let error as AuthError {
            if case .cancelled = error { }
        } catch { }
        isRevealingHistory = false
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private static let lastUsedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private func revealPassword(_ item: VaultItem) async {
        isRevealing = true
        revealError = nil
        do {
            let secret = try await repository.revealSecret(id: item.id)
            revealedPassword = secret.password
            revealedSecret = secret
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
}