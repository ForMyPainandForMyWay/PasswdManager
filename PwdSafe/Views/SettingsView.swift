import SwiftUI

enum AuthPolicy: String, CaseIterable, Sendable {
    case everyTime = "everyTime"
    case session5min = "session5min"

    var displayName: String {
        switch self {
        case .everyTime: return "每次认证"
        case .session5min: return "3 分钟内免重复认证"
        }
    }
}

enum ClipboardTimeout: Int, CaseIterable, Sendable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
    case never = 0

    var displayName: String {
        switch self {
        case .seconds15: return "15 秒"
        case .seconds30: return "30 秒"
        case .seconds60: return "60 秒"
        case .never: return "不清除"
        }
    }
}

enum AutoLockTimeout: Int, CaseIterable, Sendable {
    case minute1 = 1
    case minute5 = 5
    case minute15 = 15
    case never = 0

    var displayName: String {
        switch self {
        case .minute1: return "1 分钟"
        case .minute5: return "5 分钟"
        case .minute15: return "15 分钟"
        case .never: return "永不"
        }
    }
}

enum TrashAutoCleanup: Int, CaseIterable, Sendable {
    case never = 0
    case days30 = 30
    case days90 = 90

    var displayName: String {
        switch self {
        case .never: return "不自动清理"
        case .days30: return "30 天后自动清理"
        case .days90: return "90 天后自动清理"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("authPolicy") private var authPolicy: String = AuthPolicy.session5min.rawValue
    @AppStorage("clipboardTimeout") private var clipboardTimeout: Int = ClipboardTimeout.seconds30.rawValue
    @AppStorage("autoLockTimeout") private var autoLockTimeout: Int = AutoLockTimeout.minute5.rawValue
    @AppStorage("trashAutoCleanup") private var trashAutoCleanup: Int = TrashAutoCleanup.never.rawValue

    @State private var selectedAuthPolicy: AuthPolicy = .session5min
    @State private var selectedClipboardTimeout: ClipboardTimeout = .seconds30
    @State private var selectedAutoLockTimeout: AutoLockTimeout = .minute5
    @State private var selectedTrashAutoCleanup: TrashAutoCleanup = .never

    var body: some View {
        NavigationStack {
            TabView {
                securityTab
                    .tabItem {
                        Label("安全", systemImage: "lock.shield.fill")
                    }

                generalTab
                    .tabItem {
                        Label("通用", systemImage: "gear")
                    }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            selectedAuthPolicy = AuthPolicy(rawValue: authPolicy) ?? .session5min
            selectedClipboardTimeout = ClipboardTimeout(rawValue: clipboardTimeout) ?? .seconds30
            selectedAutoLockTimeout = AutoLockTimeout(rawValue: autoLockTimeout) ?? .minute5
            selectedTrashAutoCleanup = TrashAutoCleanup(rawValue: trashAutoCleanup) ?? .never
        }
    }

    private var securityTab: some View {
        Form {
            Section {
                Picker("认证策略", selection: $selectedAuthPolicy) {
                    ForEach(AuthPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .onChange(of: selectedAuthPolicy) { _, newValue in
                    authPolicy = newValue.rawValue
                }

                Text("选择查看密码时是否需要每次都进行 Touch ID / Apple Watch 认证，还是在 3 分钟内免重复认证。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("认证")
            }

            Section {
                Picker("自动锁定", selection: $selectedAutoLockTimeout) {
                    ForEach(AutoLockTimeout.allCases, id: \.self) { timeout in
                        Text(timeout.displayName).tag(timeout)
                    }
                }
                .onChange(of: selectedAutoLockTimeout) { _, newValue in
                    autoLockTimeout = newValue.rawValue
                }

                Text("App 进入后台或闲置超过设定时间后自动锁定保险库。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("锁定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Section {
                Picker("剪贴板清除", selection: $selectedClipboardTimeout) {
                    ForEach(ClipboardTimeout.allCases, id: \.self) { timeout in
                        Text(timeout.displayName).tag(timeout)
                    }
                }
                .onChange(of: selectedClipboardTimeout) { _, newValue in
                    clipboardTimeout = newValue.rawValue
                }

                Text("复制密码后自动清除剪贴板的等待时间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("剪贴板")
            }

            Section {
                Picker("回收站自动清理", selection: $selectedTrashAutoCleanup) {
                    ForEach(TrashAutoCleanup.allCases, id: \.self) { cleanup in
                        Text(cleanup.displayName).tag(cleanup)
                    }
                }
                .onChange(of: selectedTrashAutoCleanup) { _, newValue in
                    trashAutoCleanup = newValue.rawValue
                }

                Text("回收站中的条目在设定天数后自动永久删除。建议设置为「不自动清理」以避免误删。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("回收站")
            }

            Section {
                LabeledContent("版本", value: "1.0.0 (M3)")
                LabeledContent("构建平台", value: "macOS 26.0")
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}