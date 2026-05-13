import SwiftUI

private let presetColors: [(String, String)] = [
    ("#FF3B30", "红色"),
    ("#FF9500", "橙色"),
    ("#FFCC00", "黄色"),
    ("#34C759", "绿色"),
    ("#007AFF", "蓝色"),
    ("#AF52DE", "紫色"),
    ("#32ADE6", "青色"),
    ("#8E8E93", "灰色"),
]

struct SidebarView: View {
    let repository: VaultRepository
    @Binding var selectedNavigation: NavigationItem
    @State private var showGroupSheet: Bool = false
    @State private var showTagSheet: Bool = false
    @State private var editingGroup: VaultGroup?
    @State private var editingTag: VaultTag?
    @State private var groupsExpanded: Bool = true
    @State private var tagsExpanded: Bool = true

    var body: some View {
        List(selection: $selectedNavigation) {
            Section {
                ForEach(systemItems, id: \.id) { item in
                    NavigationLink(value: item) {
                        Label(item.title, systemImage: item.iconName)
                    }
                }
            }

            Section {
                if groupsExpanded {
                    ForEach(repository.groups) { group in
                        NavigationLink(value: NavigationItem.group(group.id)) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color(hex: group.colorHex) ?? .accentColor)
                                Text(group.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    editingGroup = group
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contextMenu {
                            Button("编辑...") {
                                editingGroup = group
                            }
                            Divider()
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
            } header: {
                HStack(spacing: 0) {
                    Text("分组")
                        .font(.body)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            groupsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(groupsExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                }
            }

            Section {
                if tagsExpanded {
                    ForEach(repository.tags) { tag in
                        NavigationLink(value: NavigationItem.tag(tag.id)) {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(Color(hex: tag.colorHex) ?? .accentColor)
                                Text(tag.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    editingTag = tag
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contextMenu {
                            Button("编辑...") {
                                editingTag = tag
                            }
                            Divider()
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
            } header: {
                HStack(spacing: 0) {
                    Text("标签")
                        .font(.body)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            tagsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(tagsExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
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
        .sheet(item: $editingGroup) { group in
            EditGroupSheet(repository: repository, group: group)
        }
        .sheet(item: $editingTag) { tag in
            EditTagSheet(repository: repository, tag: tag)
        }
    }

    private var systemItems: [NavigationItem] {
        [.allItems, .favorites, .trash]
    }
}

// MARK: - Color Mix Picker

private struct ColorMixPicker: View {
    let colorOptions: [(String, String)]
    @Binding var selectedHexes: [String]

    @Namespace private var ns
    @State private var isExpanded: Bool = false
    @State private var showIcons: Bool = false
    @State private var hoveredAddHex: String?
    @State private var hoveredRemoveHex: String?
    @State private var removedQueue: [String] = []

    private var availableColors: [(String, String)] {
        let availableSet = colorOptions.filter { !selectedHexes.contains($0.0) }
        var result: [(String, String)] = []
        for hex in removedQueue {
            if let match = availableSet.first(where: { $0.0 == hex }) {
                result.append(match)
            }
        }
        for opt in availableSet {
            if !result.contains(where: { $0.0 == opt.0 }) {
                result.append(opt)
            }
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: isExpanded ? 4 : -10) {
                ForEach(selectedHexes, id: \.self) { hex in
                    selectedCircle(hex: hex)
                }
            }
            .padding(.trailing, 4)

            if !availableColors.isEmpty {
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 6)

                HStack(spacing: 4) {
                    ForEach(availableColors, id: \.0) { hex, _ in
                        availableCircle(hex: hex)
                    }
                }
                .frame(minWidth: 24, alignment: .leading)
            }
        }
        .onHover { hovering in
            if hovering {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if isExpanded {
                        showIcons = true
                    }
                }
            } else {
                showIcons = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
        .onChange(of: selectedHexes) { _, _ in
            if selectedHexes.isEmpty {
                selectedHexes = ["#007AFF"]
            }
        }
    }

    private func selectedCircle(hex: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: hex) ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            if showIcons {
                if hoveredRemoveHex == hex {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .contentShape(Circle())
        .matchedGeometryEffect(id: hex, in: ns)
        .zIndex(1)
        .onHover { hovering in
            hoveredRemoveHex = hovering ? hex : nil
        }
        .onTapGesture {
            if selectedHexes.count > 1 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    removedQueue.insert(hex, at: 0)
                    selectedHexes.removeAll { $0 == hex }
                }
            }
        }
    }

    private func availableCircle(hex: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: hex) ?? .gray)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.secondary.opacity(0.25), lineWidth: 1))
            if hoveredAddHex == hex {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
        .matchedGeometryEffect(id: hex, in: ns)
        .zIndex(1)
        .onHover { hovering in
            hoveredAddHex = hovering ? hex : nil
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                removedQueue.removeAll { $0 == hex }
                selectedHexes.append(hex)
            }
        }
    }
}

private func mixHex(_ hexes: [String]) -> String {
    guard !hexes.isEmpty else { return "#007AFF" }
    var rSum = 0, gSum = 0, bSum = 0
    for hex in hexes {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { continue }
        rSum += Int((value >> 16) & 0xFF)
        gSum += Int((value >> 8) & 0xFF)
        bSum += Int(value & 0xFF)
    }
    let count = hexes.count
    return String(format: "#%02X%02X%02X", rSum / count, gSum / count, bSum / count)
}

// MARK: - Create Group Sheet

private struct CreateGroupSheet: View {
    let repository: VaultRepository
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @State private var selectedHexes: [String] = ["#007AFF"]

    private var colorHex: String { mixHex(selectedHexes) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $name)
                ColorMixPicker(colorOptions: presetColors, selectedHexes: $selectedHexes)
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
                        repository.createGroup(name: name, colorHex: colorHex, colorHexes: selectedHexes)
                        isPresented = false
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 180)
    }
}

// MARK: - Create Tag Sheet

private struct CreateTagSheet: View {
    let repository: VaultRepository
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @State private var selectedHexes: [String] = ["#007AFF"]

    private var colorHex: String { mixHex(selectedHexes) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标签名称", text: $name)
                ColorMixPicker(colorOptions: presetColors, selectedHexes: $selectedHexes)
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
                        repository.createTag(name: name, colorHex: colorHex, colorHexes: selectedHexes)
                        isPresented = false
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 180)
    }
}

// MARK: - Edit Group Sheet

private struct EditGroupSheet: View {
    let repository: VaultRepository
    let group: VaultGroup
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedHexes: [String]

    private var colorHex: String { mixHex(selectedHexes) }

    init(repository: VaultRepository, group: VaultGroup) {
        self.repository = repository
        self.group = group
        let hexes = group.colorHexes ?? [group.colorHex ?? "#007AFF"]
        self._name = State(initialValue: group.name)
        self._selectedHexes = State(initialValue: hexes)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $name)
                ColorMixPicker(colorOptions: presetColors, selectedHexes: $selectedHexes)
            }
            .formStyle(.grouped)
            .navigationTitle("编辑分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !name.isEmpty else { return }
                        repository.updateGroup(id: group.id, name: name, colorHex: colorHex, colorHexes: selectedHexes)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 180)
    }
}

// MARK: - Edit Tag Sheet

private struct EditTagSheet: View {
    let repository: VaultRepository
    let tag: VaultTag
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedHexes: [String]

    private var colorHex: String { mixHex(selectedHexes) }

    init(repository: VaultRepository, tag: VaultTag) {
        self.repository = repository
        self.tag = tag
        let hexes = tag.colorHexes ?? [tag.colorHex ?? "#007AFF"]
        self._name = State(initialValue: tag.name)
        self._selectedHexes = State(initialValue: hexes)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标签名称", text: $name)
                ColorMixPicker(colorOptions: presetColors, selectedHexes: $selectedHexes)
            }
            .formStyle(.grouped)
            .navigationTitle("编辑标签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !name.isEmpty else { return }
                        repository.updateTag(id: tag.id, name: name, colorHex: colorHex, colorHexes: selectedHexes)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 180)
    }
}
