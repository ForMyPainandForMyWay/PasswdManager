import SwiftUI

@main
struct PwdSafeApp: App {
    var body: some Scene {
        WindowGroup {
            VaultWindowView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建密码条目") {
                    NotificationCenter.default.post(
                        name: .createNewItem,
                        object: nil
                    )
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("保险库") {
                Button("搜索密码条目") {
                    NotificationCenter.default.post(
                        name: .focusSearch,
                        object: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("锁定 PwdSafe") {
                    NotificationCenter.default.post(
                        name: .lockVault,
                        object: nil
                    )
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            SidebarCommands()
        }
    }
}

extension Notification.Name {
    static let createNewItem = Notification.Name("PwdSafe.createNewItem")
    static let lockVault = Notification.Name("PwdSafe.lockVault")
    static let focusSearch = Notification.Name("PwdSafe.focusSearch")
}
