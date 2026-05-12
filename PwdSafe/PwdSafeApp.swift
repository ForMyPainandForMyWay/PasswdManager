import SwiftUI
import SwiftData

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
            SidebarCommands()
        }
    }
}

extension Notification.Name {
    static let createNewItem = Notification.Name("PwdSafe.createNewItem")
}