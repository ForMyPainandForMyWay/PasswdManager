import SwiftUI

struct TrashView: View {
    let repository: VaultRepository

    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID> = []
    @State private var pendingDeleteIDs: [UUID] = []
    @State private var showDeleteConfirmation: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if repository.trashedItems.isEmpty {
                    emptyTrashView
                } else {
                    trashList
                }
            }
            .navigationTitle("回收站")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !repository.trashedItems.isEmpty {
                        Menu {
                            Button {
                                repository.restoreFromTrash(ids: Array(selectedIDs))
                                selectedIDs.removeAll()
                            } label: {
                                Label("恢复选中", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(selectedIDs.isEmpty)

                            Divider()

                            Button(role: .destructive) {
                                pendingDeleteIDs = Array(selectedIDs)
                                showDeleteConfirmation = true
                            } label: {
                                Label("永久删除选中", systemImage: "trash.slash")
                            }
                            .disabled(selectedIDs.isEmpty)

                            Divider()

                            Button(role: .destructive) {
                                pendingDeleteIDs = repository.trashedItems.map(\.id)
                                showDeleteConfirmation = true
                            } label: {
                                Label("清空回收站", systemImage: "xmark.bin")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "永久删除",
                isPresented: $showDeleteConfirmation
            ) {
                Button("永久删除", role: .destructive) {
                    Task {
                        do {
                            try await repository.permanentlyDelete(ids: pendingDeleteIDs)
                        } catch {
                            repository.permanentlyDeleteWithoutAuth(ids: pendingDeleteIDs)
                        }
                        selectedIDs.removeAll()
                        pendingDeleteIDs = []
                    }
                }
                Button("取消", role: .cancel) {
                    pendingDeleteIDs = []
                }
            } message: {
                Text("选中的 \(pendingDeleteIDs.count) 个项目将被永久删除，此操作不可撤销。")
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 480)
    }

    private var emptyTrashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("回收站为空")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("删除的密码条目会出现在这里")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trashList: some View {
        List(selection: $selectedIDs) {
            Section {
                ForEach(repository.trashedItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                        HStack(spacing: 8) {
                            if let username = item.username, !username.isEmpty {
                                Text(username)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let deletedAt = item.deletedAt {
                                Text("删除于 \(deletedAt, style: .relative) 前")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .leading) {
                        Button {
                            repository.restoreFromTrash(ids: [item.id])
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            repository.permanentlyDeleteWithoutAuth(ids: [item.id])
                            selectedIDs.remove(item.id)
                        } label: {
                            Label("永久删除", systemImage: "trash.slash")
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}