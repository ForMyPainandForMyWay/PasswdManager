# macOS 自用版密码管理器开发规划书

生成日期：2026-05-12  
定位：个人自用、macOS 优先、本地优先、尽量少折腾但保留基础安全  
主技术栈：Swift、SwiftUI、SwiftData、Keychain Services、CryptoKit、LocalAuthentication、CloudKit

> 重要边界：macOS App 不能直接要求或校验用户的 Apple 账户密码。可行方案是：使用当前 macOS 登录用户的 Keychain、Touch ID / Apple Watch / 本机登录密码认证，以及 CloudKit 的 iCloud 登录状态。也就是说，本项目不做独立账号系统、不做 App 主密码，访问敏感数据时使用系统级本机认证。

---

## 一、简化后的项目目标

### 1. 优先目标

- 做一个原生 macOS 密码管理器。
- 本地可独立使用，不依赖服务器。
- 使用 SwiftData 管理条目、分组、标签、图标、回收站等非密码数据。
- 使用 Keychain + CryptoKit 存储密码、备注、TOTP 种子等敏感数据。
- 使用 Touch ID / Apple Watch / 本机登录密码解锁或显示敏感字段。
- 使用 CloudKit 作为可选 iCloud 同步，不做自建 Vapor 服务。
- 支持回收站，不做复杂删除恢复流程。
- 自动填充能力拆成独立后续任务，不阻塞主 App。

### 2. 明确砍掉的复杂功能

- 砍掉高隐私模式：标题、网址、用户名、分组、标签可以明文保存在本机 SwiftData 中。
- 砍掉设备配对：不做 QR 配对、可信设备握手、跨设备密钥转移流程。
- 砍掉复杂恢复密钥：不强制设计 24 词恢复码；依赖 Keychain、iCloud 与本机备份。
- 砍掉企业级零知识证明表述：保留“客户端加密后同步”，不做复杂证明协议。
- 砍掉健康评分、泄露探测、弱密码大盘：后续有兴趣再作为独立增强功能。
- 砍掉共享保险库、团队权限、审计日志、服务器端同步。
- 砍掉 AutoFill 主线任务：另写独立任务书，主 App 先完成。

### 3. 自用版安全原则

- 不存明文密码。
- 不上传明文密码。
- 不自建账号系统。
- 不把密码写入日志、崩溃信息或调试输出。
- App 锁定后详情页不能继续显示明文。
- 删除先进入回收站，回收站清空时再删除 Keychain 密文。
- 只要涉及“查看、复制、编辑密码”，都要求系统认证。

---

## 二、macOS App 功能范围

### 1. 第一版必须完成

- 创建、编辑、删除密码条目。
- 分组管理。
- 标签管理。
- 搜索标题、网址、用户名、备注摘要。
- 查看/复制用户名、密码、TOTP、备注。
- 密码生成器。
- Touch ID / Apple Watch / 本机登录密码认证。
- 回收站与恢复。
- 本地导入/导出加密备份。
- 可选 CloudKit 同步。

### 2. 第一版暂不完成

- Safari / App 自动填充。
- iOS / iPadOS 客户端。
- 企业共享与团队权限。
- 密码泄露检测。
- 自动网站图标抓取。
- 浏览器插件。
- 复杂恢复密钥体系。

---

## 三、系统架构

```text
PwdSafe macOS App
        │
SwiftUI Views
        │
ViewModels
        │
VaultRepository
        ├── SwiftDataStore       // 条目索引、分组、标签、回收站
        ├── KeychainStore        // 敏感密文和主密钥包装结果
        ├── CryptoService        // AES-GCM 加密/解密
        ├── AuthService          // LocalAuthentication
        └── CloudKitSyncService  // 可选 iCloud 同步
```

设计取舍：

- 主 App 使用 SwiftUI，必要时用 AppKit 补足 macOS 菜单、快捷键、窗口行为。
- 不拆复杂多 target；第一版只有 macOS App target。
- AutoFill Extension 后续独立新增，不影响当前数据层接口。
- 先做本地能力，再做 CloudKit 同步；同步层不应阻塞本地 CRUD。

---

## 四、数据模型设计

### 1. SwiftData 存储内容

SwiftData 保存方便本机检索和展示的非核心敏感数据。

```swift
import Foundation
import SwiftData

@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var website: String?
    var username: String?
    var notePreview: String?
    var iconName: String?
    var secretRef: String
    var isFavorite: Bool
    var isDeleted: Bool
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \VaultGroup.items)
    var group: VaultGroup?

    @Relationship
    var tags: [VaultTag]
}

@Model
final class VaultGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \VaultItem.group)
    var items: [VaultItem]
}

@Model
final class VaultTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String?
    var createdAt: Date
    var updatedAt: Date
}
```

### 2. Keychain 存储内容

Keychain 保存敏感载荷的密文，不直接保存明文。

```swift
struct SecretPayload: Codable, Sendable {
    var password: String
    var secureNote: String?
    var totpSeed: String?
    var customFields: [SecretField]
}

struct SecretField: Codable, Hashable, Sendable {
    var name: String
    var value: String
    var isHidden: Bool
}

struct EncryptedSecret: Codable, Sendable {
    var version: Int
    var algorithm: String
    var keyID: String
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}
```

Keychain item 建议：

- `kSecClassGenericPassword`
- `kSecAttrService = "PwdSafe.Secret"`
- `kSecAttrAccount = secretRef`
- `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- 使用 `SecAccessControl` 让读取或解密前触发本机用户认证。

### 3. 为什么仍然加密后再进 Keychain

Keychain 本身已经是系统安全存储，但自用密码管理器最好仍然保留一层应用级密文：

- CloudKit 同步时可直接同步密文。
- 后续做导出备份时可复用同一密文格式。
- 数据结构更清晰，方便迁移和审计。
- 即使 SwiftData 误存了 `secretRef`，也拿不到明文。

---

## 五、认证与解锁

### 1. 认证方式

使用 `LocalAuthentication` 的 `.deviceOwnerAuthentication`。

在 macOS 上这通常表示：

- Touch ID。
- Apple Watch 解锁确认。
- 本机登录密码。

不建议使用“Apple 账户密码”作为 App 解锁方式，因为普通 App 没有直接验证 Apple ID 密码的系统 API。

### 2. 解锁策略

- 启动 App 后可以先展示列表，但不展示密码。
- 查看、复制、编辑敏感字段前要求认证。
- 认证通过后创建短期解锁会话，默认有效 5 分钟。
- App 进入后台、锁屏或睡眠后立即清除解锁会话。
- 用户可以在设置里选择“每次复制密码都认证”或“5 分钟内免重复认证”。

### 3. AuthService 接口

```swift
import LocalAuthentication

protocol AuthService: Sendable {
    func authenticate(reason: String) async throws
    func canAuthenticate() -> Bool
}

enum AuthError: Error {
    case unavailable
    case cancelled
    case failed
}
```

---

## 六、加密方案

### 1. 简化密钥策略

第一版采用一个本机 Vault Key：

- 初次启动时生成 256-bit 随机 `VaultKey`。
- `VaultKey` 存入 Keychain，并受本机认证保护。
- 每个密码条目使用 `VaultKey + itemID` 派生条目密钥。
- 条目载荷使用 `AES.GCM` 加密。

这样避免了：

- 主密码。
- 复杂恢复密钥。
- 设备配对。
- 多层密钥轮换。

代价是：

- 如果 Keychain 数据丢失且没有备份，保险库无法恢复。
- 换 Mac 时依赖 iCloud Keychain / 迁移助理 / 加密导出备份，而不是自研配对流程。

### 2. CryptoService 接口

```swift
import CryptoKit
import Foundation

protocol CryptoService: Sendable {
    func createVaultKey() throws -> SymmetricKey
    func encrypt(_ payload: SecretPayload, itemID: UUID, vaultKey: SymmetricKey) throws -> EncryptedSecret
    func decrypt(_ encrypted: EncryptedSecret, itemID: UUID, vaultKey: SymmetricKey) throws -> SecretPayload
}
```

### 3. 加密注意事项

- `AES.GCM` 每次加密使用新 nonce。
- 解密失败统一显示“密码数据无法验证”，不要暴露内部错误。
- `itemID`、`version`、`secretRef` 应作为 AAD 的一部分。
- 修改密码时创建新密文，不原地修改旧密文。

---

## 七、核心业务接口

### 1. VaultRepository

```swift
protocol VaultRepository: Sendable {
    func createItem(_ draft: VaultItemDraft) async throws -> UUID
    func updateItem(id: UUID, mutation: VaultItemMutation) async throws
    func revealSecret(id: UUID, reason: String) async throws -> SecretPayload
    func copyPassword(id: UUID) async throws
    func moveToTrash(ids: [UUID]) async throws
    func restoreFromTrash(ids: [UUID]) async throws
    func permanentlyDelete(ids: [UUID], reason: String) async throws
    func search(_ query: String, includeTrash: Bool) async throws -> [VaultItemSummary]
}

struct VaultItemDraft: Sendable {
    var title: String
    var website: String?
    var username: String?
    var groupID: UUID?
    var tagIDs: [UUID]
    var secret: SecretPayload
}

struct VaultItemMutation: Sendable {
    var title: String?
    var website: String?
    var username: String?
    var groupID: UUID?
    var tagIDs: [UUID]?
    var secret: SecretPayload?
}
```

### 2. 业务事务规则

- 新建：认证 → 生成 `secretRef` → 加密 → 写 Keychain → 写 SwiftData。
- 编辑：认证 → 读取旧记录 → 生成新密文 → 更新 Keychain → 更新 SwiftData。
- 查看：认证 → 读取 Keychain → 解密 → 返回短生命周期明文。
- 删除：只改 `isDeleted = true`，不删 Keychain。
- 恢复：只改 `isDeleted = false`。
- 永久删除：认证 → 删除 Keychain → 删除 SwiftData。

---

## 八、回收站设计

### 1. 规则

- 删除条目默认进入回收站。
- 回收站中保留完整条目和密文。
- 用户可以恢复到原分组。
- 清空回收站前要求本机认证。
- 永久删除后不提供 App 内恢复。

### 2. 自动清理

可选设置：

- 不自动清理。
- 30 天后自动清理。
- 90 天后自动清理。

自用版建议默认“不自动清理”，避免误删。

---

## 九、CloudKit 同步简化方案

### 1. 定位

CloudKit 只是同步渠道，不是账号系统，也不是解锁凭据。

同步条件：

- 用户已登录 iCloud。
- 用户在 App 设置里开启 iCloud 同步。
- 本地已有可用 Vault Key。

### 2. 同步内容

同步 SwiftData 元数据和 Keychain 密文对应的 `EncryptedSecret`。

CloudKit record 示例：

```swift
struct CloudItemRecord: Codable, Sendable {
    var id: UUID
    var title: String
    var website: String?
    var username: String?
    var groupName: String?
    var tagNames: [String]
    var isDeleted: Bool
    var deletedAt: Date?
    var updatedAt: Date
    var encryptedSecret: EncryptedSecret
}
```

### 3. 同步策略

- 本地优先，离线可用。
- `updatedAt` 晚者优先。
- 如果同一条目在两台 Mac 上同时编辑，保留本地版本并创建“冲突副本”。
- CloudKit 拉取失败不影响本地使用。
- 清空回收站同步为远端删除或 tombstone。

### 4. 简化后的风险接受

由于砍掉高隐私模式：

- CloudKit 可能同步标题、网址、用户名等元数据明文。
- 密码、TOTP、密文备注仍保持加密。
- 对自用项目而言，这个复杂度和安全性比较平衡。

---

## 十、macOS 前端规划

### 1. 主窗口布局

```text
Sidebar
 ├── 全部项目
 ├── 收藏
 ├── 分组列表
 ├── 标签列表
 └── 回收站

Content List
 ├── 搜索框
 ├── 条目列表
 └── 排序/过滤

Detail Panel
 ├── 标题 / 网址 / 用户名
 ├── 密码显示与复制
 ├── TOTP
 ├── 安全备注
 └── 编辑按钮
```

### 2. 推荐 SwiftUI 视图

- `VaultWindowView`
- `SidebarView`
- `ItemListView`
- `ItemDetailView`
- `ItemEditorView`
- `TrashView`
- `SettingsView`
- `PasswordGeneratorView`
- `AuthenticationPromptCoordinator`

### 3. macOS 交互细节

- 支持菜单栏命令：新增、搜索、锁定、导入、导出。
- 支持快捷键：
  - `⌘N` 新建密码。
  - `⌘F` 搜索。
  - `⌘L` 锁定。
  - `⌘C` 复制当前选中字段。
- 密码字段默认隐藏。
- 复制密码后 30 秒清空剪贴板。
- App 锁定时详情区显示占位，不显示敏感字段。

---

## 十一、导入导出与备份

### 1. 导出

第一版只支持加密导出：

- 导出为 `.pwdsafe-backup`。
- 文件包含 SwiftData 元数据和所有 `EncryptedSecret`。
- 导出前要求本机认证。
- 可选再输入一个临时备份密码加密整个备份文件。

### 2. 导入

- 选择 `.pwdsafe-backup`。
- 验证文件格式。
- 如设置了备份密码，先解密。
- 导入为新条目或合并现有条目。
- 冲突时保留两个版本。

### 3. 暂不支持

- 明文 CSV 导出默认不做。
- 如果后续确实需要迁移，可放到“高级设置”，并显示强提醒。

---

## 十二、开发里程碑

### M1：本地数据骨架

- 创建 macOS SwiftUI 项目。
- 建立 SwiftData models。
- 完成列表、详情、编辑页的假数据 UI。
- 完成分组、标签、回收站基础操作。

### M2：Keychain 与加密

- 实现 `AuthService`。
- 实现 `CryptoService`。
- 实现 `KeychainStore`。
- 接入真实创建、查看、复制、编辑密码。
- 添加复制后清空剪贴板。

### M3：本地完整可用

- 完成密码生成器。
- 完成搜索与过滤。
- 完成导入/导出加密备份。
- 完成设置页。
- 完成基础单元测试。

### M4：CloudKit 同步

- 添加 iCloud 开关。
- 建立 CloudKit private database record。
- 实现本地变更上传。
- 实现远端变更拉取。
- 实现简单冲突副本。

### M5：打磨与自用发布

- 优化 macOS 快捷键、菜单栏、窗口体验。
- 做真机/真 Mac 长时间使用测试。
- 修复崩溃和数据迁移问题。
- 整理 README 与使用说明。

---

## 十三、测试清单

### 1. 必测安全场景

- 未认证时不能查看密码。
- 认证取消后不能查看密码。
- App 锁定后不能继续复制密码。
- 密文被篡改后解密失败。
- Keychain 条目不存在时 UI 友好报错。
- 清空回收站前必须认证。
- 复制密码后剪贴板能自动清空。

### 2. 必测数据场景

- 新建、编辑、删除、恢复、永久删除。
- 分组删除后条目仍然存在。
- 标签删除后条目仍然存在。
- 搜索标题、网址、用户名正常。
- App 重启后数据仍然存在。
- SwiftData schema 变更后能迁移。

### 3. 必测同步场景

- iCloud 未登录时本地可用。
- 断网时本地可用。
- 恢复网络后同步。
- 两台 Mac 同时编辑同一条目时生成冲突副本。
- 回收站状态能同步。
- 永久删除能同步。

---

## 十四、建议的第一批文件结构

```text
PwdSafe/
 ├── PwdSafeApp.swift
 ├── Models/
 │   ├── VaultItem.swift
 │   ├── VaultGroup.swift
 │   └── VaultTag.swift
 ├── Services/
 │   ├── AuthService.swift
 │   ├── CryptoService.swift
 │   ├── KeychainStore.swift
 │   └── CloudKitSyncService.swift
 ├── Repositories/
 │   └── VaultRepository.swift
 ├── Views/
 │   ├── VaultWindowView.swift
 │   ├── SidebarView.swift
 │   ├── ItemListView.swift
 │   ├── ItemDetailView.swift
 │   ├── ItemEditorView.swift
 │   └── SettingsView.swift
 └── Utilities/
     ├── ClipboardCleaner.swift
     └── PasswordGenerator.swift
```

---

## 十五、最终自用版路线总结

第一阶段不要追求“像 1Password 一样完整”，而是先做到：

- 本机能安全保存密码。
- 本机认证体验顺滑。
- 数据结构清晰可迁移。
- 删除恢复简单可靠。
- 可选 iCloud 同步够用。
- 自动填充以后再接。

这个版本的关键不是堆安全名词，而是把“不会明文泄露密码、不会误删、日常使用不烦人”做好。
