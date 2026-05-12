# 密码管理器 App 开发规划书

生成日期：2026-05-12  
目标平台：macOS，后续可扩展iOS/iPadOS 与 visionOS  
技术约束：100% Swift、SwiftData、Keychain Services、CryptoKit、Secure Enclave、LocalAuthentication、SwiftUI、Credential Provider Extension、CloudKit 或 Server-Side Swift/Vapor

> 安全术语说明：本文中的“零知识架构”指密码管理器行业常用的“服务端/云端零知识”模型，即云端只能保存密文、同步元数据和不可逆索引，不能解密用户密码。它不是每次同步都运行交互式 Zero-Knowledge Proof 协议；如果未来要做共享保险库、企业托管或防撞库证明，可另行引入 PAKE/OPAQUE、签名证明或可验证同步日志。

---

## 阶段一：系统架构设计 (Architecture)

### 1. 总体架构分层

建议先完成“核心安全层 + 本地数据层 + 同步层”，再接 UI 与系统扩展。

```text
SwiftUI / Credential Provider Extension
        │
VaultViewModel / TCA Feature
        │
VaultRepository
        ├── SwiftDataMetadataStore      // 本地非敏感索引、分组、标签、图标
        ├── KeychainSecretStore         // 本地敏感密文与密钥包装材料
        ├── CryptoEngine                // AES-GCM、HKDF、HMAC、密钥派生
        ├── MasterKeyManager            // Secure Enclave + Recovery Key + 解锁会话
        └── CloudSyncService            // CloudKit 私有库零知识同步
```

### 2. 数据流转路径

#### 2.1 新建或编辑密码条目

1. 用户在前端输入标题、网址、用户名、密码、TOTP 种子、安全备注、分组和标签。
2. `VaultRepository` 将输入拆成两类：
   - 本地可索引元数据：`itemID`、分组、标签、图标、排序、收藏状态、本地更新时间。
   - 敏感载荷：密码、TOTP 种子、安全备注、隐藏字段、恢复码；高安全模式下用户名、URL 标题也进入敏感载荷。
3. `CryptoEngine` 使用当前解锁会话中的 `VaultRootKey` 派生 `ItemContentKey`，通过 `AES.GCM` 加密 `SecretPayload`。
4. 加密结果封装为 `EncryptedSecretEnvelope`，包含算法版本、nonce、ciphertext、tag、AAD 摘要、keyID、schemaVersion。
5. `KeychainSecretStore` 以 `secretRef = "vault.item.<UUID>"` 为 account，将密文 envelope 写入 Keychain。
6. `SwiftDataMetadataStore` 保存 `VaultItemMetadata`，只保留 `secretRef` 与非敏感索引，不存明文密码。
7. `CloudSyncService` 将“云端记录密文”写入 CloudKit 私有库自定义 zone。云端可使用 CloudKit `encryptedValues` 作为第二层保护，但不能代替客户端加密。

#### 2.2 读取密码条目

1. UI 先读取 SwiftData 元数据，快速展示列表、分组、标签和图标。
2. 用户进入详情页或触发自动填充时，`VaultRepository` 要求 `MasterKeyManager` 提供已解锁的 `VaultRootKey`。
3. `KeychainSecretStore` 读取 `secretRef` 对应 envelope。
4. `CryptoEngine` 用 `VaultRootKey` 派生 `ItemContentKey`，验证 AAD 和 `AES.GCM` tag 后解密。
5. 明文只存在于短生命周期内存对象，App 进入后台、超时或截图保护触发时立即销毁解锁会话。

#### 2.3 CloudKit 同步

1. 本地变更写入 SwiftData 和 Keychain 成功后，生成 `PendingSyncOperation`。
2. 同步层将用户内容统一编码为 `CloudVaultPayload` 并在本地加密。
3. CloudKit 只保存：
   - `recordName` / `itemID`
   - `recordType`
   - `updatedAt`
   - `deviceID`
   - `schemaVersion`
   - `tombstone`
   - `encryptedBlob`
   - 可选的不可逆检索标签，如 `HMAC(IndexKey, normalizedDomain)`
4. 其他设备拉取 CloudKit record change 后，先验证版本、签名或 HMAC，再用本地解锁得到的 `VaultRootKey` 解密，最后重建 SwiftData 索引与本地 Keychain 密文。

### 3. 零知识架构具体方案

#### 3.1 密钥层级

```text
Recovery Key / Trusted Device Pairing
        │ wraps
Device Secure Enclave Key Pair
        │ unwraps
VaultRootKey (256-bit random, never stored plaintext)
        ├── HKDF → ItemContentKey(itemID)
        ├── HKDF → MetadataEncryptionKey
        ├── HKDF → SearchIndexKey
        ├── HKDF → CloudRecordMACKey
        └── HKDF → ExportBackupKey
```

核心原则：

- `VaultRootKey` 是高熵随机密钥，不由普通用户密码直接决定，避免弱密码拖垮整个保险库。
- Secure Enclave 不适合直接存储对称主密钥；它主要保护私钥。使用它生成设备私钥，再通过 Keychain access control 和密钥协商/包装来保护 `VaultRootKey`。
- 每个 item 使用 HKDF 派生独立内容密钥。单条记录泄露或 nonce 事故不应扩散到整个保险库。
- 搜索索引用 `HMAC(SearchIndexKey, canonicalValue)`，云端不能反推原域名或用户名，但仍可做等值匹配。
- 新设备不能只靠登录同一个 iCloud 账号解密；必须通过恢复密钥或可信设备配对获得 `VaultRootKey` 包装材料。

#### 3.2 云端被攻破时的防护

即使攻击者获得 CloudKit 私有库数据，也只能看到：

- 随机或半随机的 record ID。
- 记录大小、更新时间、删除 tombstone 等不可避免同步元数据。
- 客户端加密后的 `encryptedBlob`。
- 不可逆 HMAC 检索标签。

攻击者不能获得：

- `VaultRootKey`。
- 单条 item 的派生内容密钥。
- 明文密码、TOTP 种子、安全备注。
- 用户本地 Secure Enclave 私钥。
- 可信设备配对产生的包装密钥。

#### 3.3 恢复与多设备策略

建议提供三种恢复路径，并在 UI 中清晰告知取舍：

1. **可信设备配对**：旧设备显示一次性 QR / Nearby token，新设备生成临时公钥，旧设备验证用户后用新设备公钥包装 `VaultRootKey`。
2. **高熵恢复密钥**：首次创建保险库时生成 128-256 bit 恢复密钥，展示为 20-24 个单词或分组字符；CloudKit 只保存恢复密钥包装后的 vault key。
3. **可选主密码**：如果必须支持人类可记忆主密码，应使用经过安全评审的 KDF。仅用 HKDF 处理低熵密码不够安全；若坚持 100% Swift，可规划纯 Swift Argon2id/scrypt 模块并单独审计，否则建议只把主密码作为本地二次验证，而非云端恢复根密钥。

---

## 阶段二：“后端”与核心安全层开发规划 (Core Backend & Security)

### 1. 后端开发顺序

1. 定义威胁模型：设备丢失、CloudKit 泄露、恶意备份、Keychain 失败、越狱环境、扩展进程受限、同步冲突。
2. 实现 `CryptoEngine`：AES-GCM、HKDF 派生、HMAC 标签、密文 envelope 编解码、AAD 绑定。
3. 实现 `MasterKeyManager`：创建 vault、Secure Enclave 设备密钥、恢复密钥、解锁会话、自动锁定。
4. 实现 `KeychainSecretStore`：增删改查密文 envelope，配置 access group 供主 App 与 AutoFill 扩展共享。
5. 实现 `SwiftDataMetadataStore`：建模 Group、Tag、Item、Icon、PendingSyncOperation、Tombstone。
6. 实现 `VaultRepository`：把 SwiftData、Keychain、Crypto 事务编排成原子业务操作。
7. 实现 `CloudSyncService`：自定义 zone、变更拉取、冲突合并、重试、离线队列、云端密文 schema。
8. 做安全单测与故障注入：先不做 UI，使用命令式测试覆盖核心逻辑。

### 2. 主密钥管理

#### 2.1 设计目标

- `VaultRootKey` 只在解锁会话内以明文存在。
- 本地持久化保存的是被设备密钥或恢复密钥包装后的 root key。
- Secure Enclave 私钥需要用户在创建或使用时通过生物识别/设备密码授权。
- 生物识别变更可能导致 `.biometryCurrentSet` 保护的材料不可用，因此必须提供恢复密钥。

#### 2.2 Swift 接口草案

```swift
import CryptoKit
import Foundation
import LocalAuthentication

public struct VaultIdentifier: Hashable, Codable, Sendable {
    public let rawValue: UUID
}

public struct KeyIdentifier: Hashable, Codable, Sendable {
    public let rawValue: String
}

public struct VaultRootKey: Sendable {
    public let id: KeyIdentifier
    private let key: SymmetricKey

    public init(id: KeyIdentifier, key: SymmetricKey) {
        self.id = id
        self.key = key
    }

    public func withUnsafeSymmetricKey<T>(_ body: (SymmetricKey) throws -> T) rethrows -> T {
        try body(key)
    }
}

public struct WrappedVaultKey: Codable, Sendable {
    public let keyID: KeyIdentifier
    public let wrappingMethod: WrappingMethod
    public let ephemeralPublicKey: Data?
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data
    public let createdAt: Date
}

public enum WrappingMethod: String, Codable, Sendable {
    case secureEnclaveP256
    case recoveryKeyHKDF
    case trustedDevicePairing
}

public protocol MasterKeyManaging: Sendable {
    func createVault(context: LAContext) async throws -> VaultBootstrapMaterial
    func unlockVault(_ vaultID: VaultIdentifier, context: LAContext) async throws -> VaultSession
    func rotateVaultRootKey(_ vaultID: VaultIdentifier, context: LAContext) async throws
    func wrapForNewDevice(_ vaultID: VaultIdentifier, recipientPublicKey: Data, context: LAContext) async throws -> WrappedVaultKey
    func recoverVault(_ vaultID: VaultIdentifier, recoveryKey: RecoveryKey, context: LAContext) async throws -> VaultSession
    func lockVault(_ vaultID: VaultIdentifier) async
}

public struct VaultSession: Sendable {
    public let vaultID: VaultIdentifier
    public let rootKey: VaultRootKey
    public let unlockedAt: Date
    public let expiresAt: Date
}

public struct RecoveryKey: Sendable {
    public let wordsOrCode: String
}

public struct VaultBootstrapMaterial: Sendable {
    public let vaultID: VaultIdentifier
    public let recoveryKey: RecoveryKey
    public let wrappedVaultKey: WrappedVaultKey
}
```

#### 2.3 Secure Enclave 实现要点

- 使用 Security framework 生成 Secure Enclave P-256 私钥；配置 `kSecAttrTokenIDSecureEnclave`、`kSecAttrIsPermanent`、`kSecAttrApplicationTag`。
- 使用 `SecAccessControlCreateWithFlags` 配置 `.privateKeyUsage` 与 `.biometryCurrentSet` 或 `.userPresence`。
- 高安全模式优先 `.biometryCurrentSet`，优点是新增面容/指纹后密钥失效；缺点是用户更容易需要恢复密钥。
- 兼容性模式可使用 `.userPresence` 允许设备密码回退。
- Simulator、无 Secure Enclave 设备、企业 MDM 限制环境必须走 mock 或恢复密钥路径。

### 3. 加密引擎

#### 3.1 Envelope 格式

```swift
public struct EncryptedSecretEnvelope: Codable, Sendable {
    public let version: UInt8
    public let algorithm: ContentCipher
    public let keyID: KeyIdentifier
    public let itemID: UUID
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data
    public let aadDigest: Data
    public let createdAt: Date
}

public enum ContentCipher: String, Codable, Sendable {
    case aes256GCM
}

public struct SecretPayload: Codable, Sendable {
    public var username: String?
    public var password: String
    public var totpSeed: Data?
    public var notes: String?
    public var customFields: [SecretField]
    public var recoveryCodes: [String]
}

public struct SecretField: Codable, Hashable, Sendable {
    public let name: String
    public let value: String
    public let isConcealed: Bool
}
```

#### 3.2 CryptoEngine 协议

```swift
public protocol CryptoEngine: Sendable {
    func generateRootKey() -> VaultRootKey
    func deriveItemKey(rootKey: VaultRootKey, itemID: UUID, purpose: KeyPurpose) throws -> SymmetricKey
    func encryptSecret(_ payload: SecretPayload, itemID: UUID, rootKey: VaultRootKey, aad: Data) throws -> EncryptedSecretEnvelope
    func decryptSecret(_ envelope: EncryptedSecretEnvelope, rootKey: VaultRootKey, aad: Data) throws -> SecretPayload
    func makeSearchToken(_ value: String, rootKey: VaultRootKey, namespace: SearchNamespace) throws -> Data
    func verifyRecordMAC(_ record: CloudVaultRecord, rootKey: VaultRootKey) throws
}

public enum KeyPurpose: String, Sendable {
    case itemContent
    case metadata
    case searchIndex
    case cloudRecordMAC
}

public enum SearchNamespace: String, Sendable {
    case domain
    case username
    case title
    case tag
}
```

#### 3.3 AES-GCM 使用规范

- 每次加密使用新 nonce；不要手动复用 nonce。
- 使用 AAD 绑定 `vaultID`、`itemID`、`schemaVersion`、`secretRef`、`metadataHash`，防止密文被跨记录替换。
- 解密必须先验证 tag，失败时统一抛出 `CryptoError.authenticationFailed`，不要泄露失败细节。
- 密钥轮换时新增 envelope 版本，旧版本只读迁移，避免一次性全库重写导致同步风暴。

### 4. 数据库与安全存储隔离方案

#### 4.1 SwiftData Model 设计

```swift
import Foundation
import SwiftData

@Model
public final class VaultGroup {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var iconName: String?
    public var colorHex: String?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify) public var parent: VaultGroup?
    @Relationship(deleteRule: .cascade, inverse: \VaultGroup.parent) public var children: [VaultGroup]
    @Relationship(deleteRule: .nullify, inverse: \VaultItemMetadata.group) public var items: [VaultItemMetadata]
}

@Model
public final class VaultTag {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \VaultItemMetadata.tags) public var items: [VaultItemMetadata]
}

@Model
public final class VaultItemMetadata {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var secretRef: String
    public var displayTitle: String
    public var iconKey: String?
    public var canonicalDomainToken: Data?
    public var usernameToken: Data?
    public var cloudRecordName: String?
    public var isFavorite: Bool
    public var isDeleted: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var schemaVersion: Int

    @Relationship(deleteRule: .nullify, inverse: \VaultGroup.items) public var group: VaultGroup?
    @Relationship public var tags: [VaultTag]
}

@Model
public final class PendingSyncOperation {
    @Attribute(.unique) public var id: UUID
    public var recordName: String
    public var operation: SyncOperationKind
    public var attemptCount: Int
    public var notBefore: Date
    public var createdAt: Date
}

public enum SyncOperationKind: String, Codable {
    case upsertItem
    case deleteItem
    case upsertGroup
    case upsertTag
}
```

#### 4.2 隔离边界

- SwiftData 不保存 `password`、`totpSeed`、`recoveryCodes`、安全备注明文。
- `secretRef` 是唯一桥接键，用于从 Keychain 取密文 envelope。
- 删除条目必须分两阶段：
  1. 写 tombstone 与 pending sync。
  2. CloudKit 确认删除后清理 Keychain 密文；或者保留短期本地回收站密文。
- 分组和标签是否属于敏感信息应做产品开关：
  - 标准模式：SwiftData 明文保存，便于本地 UI 和 Spotlight 禁用状态下快速查询。
  - 高隐私模式：分组名、标题、用户名、域名全部进入加密 metadata blob，本地只缓存会话内索引。

#### 4.3 Keychain 存储接口

```swift
public protocol SecretStore: Sendable {
    func save(_ envelope: EncryptedSecretEnvelope, secretRef: String, accessGroup: String?) async throws
    func load(secretRef: String, accessGroup: String?) async throws -> EncryptedSecretEnvelope
    func update(_ envelope: EncryptedSecretEnvelope, secretRef: String, accessGroup: String?) async throws
    func delete(secretRef: String, accessGroup: String?) async throws
    func exists(secretRef: String, accessGroup: String?) async throws -> Bool
}

public enum SecretStoreError: Error, Sendable {
    case duplicateItem
    case itemNotFound
    case interactionNotAllowed
    case accessDenied
    case corruptedEnvelope
    case keychainStatus(OSStatus)
}
```

Keychain item 建议：

- `kSecClassGenericPassword`
- `kSecAttrService = "com.company.pwdsafe.vault.secret"`
- `kSecAttrAccount = secretRef`
- `kSecAttrAccessGroup` 与 AutoFill Extension 共享
- `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，避免密文随非加密备份迁移
- `kSecUseAuthenticationContext = LAContext`，让主 App 与扩展共用认证上下文

### 5. VaultRepository 业务编排

```swift
public protocol VaultRepository: Sendable {
    func createItem(_ draft: VaultItemDraft, in groupID: UUID?, tagIDs: [UUID], session: VaultSession) async throws -> UUID
    func updateItem(_ itemID: UUID, mutation: VaultItemMutation, session: VaultSession) async throws
    func revealSecret(itemID: UUID, session: VaultSession) async throws -> SecretPayload
    func moveItems(_ itemIDs: [UUID], to groupID: UUID?) async throws
    func deleteItems(_ itemIDs: [UUID], mode: DeleteMode, session: VaultSession) async throws
    func search(_ query: VaultSearchQuery, session: VaultSession?) async throws -> [VaultItemSummary]
}

public struct VaultItemDraft: Sendable {
    public var displayTitle: String
    public var canonicalDomain: String?
    public var iconKey: String?
    public var secret: SecretPayload
}

public struct VaultItemMutation: Sendable {
    public var displayTitle: String?
    public var canonicalDomain: String?
    public var iconKey: String?
    public var secret: SecretPayload?
}

public enum DeleteMode: Sendable {
    case softDelete
    case purgeImmediately
}
```

事务原则：

- 新建：先写 Keychain，再写 SwiftData；SwiftData 失败时回滚 Keychain。
- 更新：先写新 envelope，再更新 metadata version；旧 envelope 可保留到提交成功后删除。
- 删除：先写 tombstone，云端确认后清理密文。
- 同步导入：先验证和解密云端 payload，再写 Keychain，最后写 SwiftData 索引。

### 6. 数据同步层

#### 6.1 CloudKit Record Schema

```swift
public struct CloudVaultRecord: Codable, Sendable {
    public let recordName: String
    public let vaultID: UUID
    public let logicalID: UUID
    public let kind: CloudRecordKind
    public let schemaVersion: Int
    public let encryptedBlob: Data
    public let recordMAC: Data
    public let searchTokens: [Data]
    public let deviceID: String
    public let modifiedAt: Date
    public let tombstone: Bool
}

public enum CloudRecordKind: String, Codable, Sendable {
    case item
    case group
    case tag
    case vaultManifest
    case wrappedKey
}
```

CloudKit 存储建议：

- 使用 private database，不使用 public database。
- 创建自定义 zone：`VaultZone`.
- `CKRecord(recordType: "VaultBlob")` 存密文 blob。
- `encryptedValues["blob"]` 可作为防御纵深，但主要安全边界仍是客户端 `AES.GCM`。
- 不对 CloudKit 加密字段建立查询索引；需要查询的字段用不可逆 HMAC token 或本地 SwiftData 索引完成。

#### 6.2 同步协议

```swift
public protocol VaultSyncService: Sendable {
    func configureZone() async throws
    func enqueueLocalChange(_ change: LocalVaultChange) async throws
    func pushPendingChanges(session: VaultSession) async throws
    func fetchRemoteChanges(session: VaultSession) async throws -> SyncReport
    func resolveConflict(local: VaultVersion, remote: VaultVersion, session: VaultSession) async throws -> ConflictResolution
}

public struct SyncReport: Sendable {
    public let imported: Int
    public let uploaded: Int
    public let conflicts: Int
    public let failures: [SyncFailure]
}
```

冲突策略：

- 密码内容冲突：不静默覆盖，保留两个版本，UI 显示“远端版本/本机版本”。
- 分组/标签冲突：使用逻辑时钟 + 设备 ID 打破平局。
- 删除冲突：tombstone 优先，但如果远端在删除后有更新，应进入人工解决队列。
- 密钥轮换冲突：以 vault manifest version 为准，旧 key 只读解密并触发再加密。

#### 6.3 Vapor 备选路线

如果后续不使用 CloudKit，而改用 Server-Side Swift/Vapor：

- 服务端只保存用户 ID、设备公钥、密文 blob、同步游标、签名日志。
- 登录不传主密码明文；可使用 OPAQUE/PAKE 方案做认证。
- 所有业务数据仍由客户端加密；服务端只做认证、存储、推送和冲突协调。
- 需要额外承担服务器安全、审计、密钥轮换、GDPR/CCPA 删除请求和可用性成本。

---

## 阶段三：“前端”与系统集成开发规划 (Frontend & System UI)

### 1. UI 架构

建议初版采用 MVVM + Repository，等功能复杂后再迁移 TCA。

```text
AppState
 ├── LockState: locked / unlocking / unlocked / recoveryRequired
 ├── VaultState: groups / tags / items / selectedItem
 ├── SyncState: idle / syncing / conflict / offline / error
 └── ExtensionState: configured / needsPermission / limitedIndex
```

前端只依赖后端协议：

- `MasterKeyManaging`
- `VaultRepository`
- `VaultSyncService`
- `CredentialIdentityIndexing`

这样可以先用 mock 后端做 UI，再切换真实实现。

### 2. 核心视图规划

#### 2.1 应用解锁页

功能：

- Face ID / Touch ID 快速解锁。
- 设备密码 fallback，可由安全等级决定是否允许。
- 恢复密钥入口。
- 生物识别集变化提示。
- 离线可用提示。

实现要点：

- 使用 `LAContext.canEvaluatePolicy` 判断能力。
- `Info.plist` 必须包含 `NSFaceIDUsageDescription`。
- 解锁成功后只保存短期 `VaultSession`，默认 5-10 分钟无操作锁定。
- App 进入后台立即模糊 UI，并按用户设置决定是否销毁 session。

#### 2.2 仪表盘

模块：

- 最近使用。
- 收藏。
- 弱密码/重复密码/泄露风险扫描入口。
- 同步状态。
- 安全健康评分。
- 快捷新增。

安全要求：

- 默认不展示密码明文。
- 列表页不展示 TOTP seed、恢复码。
- 截屏和 App Switcher 使用隐私遮罩。

#### 2.3 群组/标签分类视图

功能：

- 多级群组树。
- 标签筛选。
- 拖拽移动条目。
- 批量编辑。
- 图标与颜色管理。

数据建模映射：

- `VaultGroup` 支持父子关系。
- `VaultTag` 支持多对多。
- `VaultItemMetadata.group` 为可选，便于“未分类”。
- 删除 group 默认不删除密码，只把 item 置为未分类；“删除分组及其中条目”必须二次确认。

#### 2.4 密码详情与编辑页

功能：

- 显示标题、域名、用户名、密码、TOTP、备注、自定义字段。
- 一键复制字段，复制后自动清空剪贴板。
- 密码生成器。
- 修改历史。
- 安全评分与重复使用提示。

安全要求：

- 明文字段用局部 state 管理，不写入日志、analytics、crash metadata。
- 复制密码时给出倒计时并清理剪贴板。
- “显示密码”需二次确认或短时认证。
- 编辑保存采用新 envelope，不在原密文上原地修改。

### 3. Credential Provider Extension 自动填充

#### 3.1 Extension 架构

```text
Host App
 ├── 维护完整 SwiftData + Keychain + CloudKit
 ├── 建立 AutoFill identity index
 └── 提供设置页，引导用户开启 AutoFill

Credential Provider Extension
 ├── 读取共享 Keychain / App Group 中的最小索引
 ├── 响应系统 serviceIdentifiers
 ├── 必要时触发生物识别认证
 └── 解密并返回 ASPasswordCredential
```

#### 3.2 必要能力

- 主 App 与扩展都启用 AutoFill Credential Provider entitlement。
- 主 App 与扩展都配置 Keychain access group。
- 如果要共享轻量索引，可配置 App Group container，但不要把明文密码写入 App Group 文件。
- 使用 `ASCredentialIdentityStore` 注册 `ASPasswordCredentialIdentity`，让系统能在 QuickType bar 显示候选。

#### 3.3 核心接口草案

```swift
import AuthenticationServices
import Foundation

public protocol CredentialIdentityIndexing: Sendable {
    func rebuildIndex(items: [VaultItemSummary]) async throws
    func upsertIdentity(for item: VaultItemSummary) async throws
    func removeIdentity(itemID: UUID) async throws
    func findCandidates(for serviceIdentifiers: [ASCredentialServiceIdentifier]) async throws -> [CredentialCandidate]
}

public struct CredentialCandidate: Sendable {
    public let itemID: UUID
    public let serviceIdentifier: String
    public let displayName: String
    public let userNameDisplay: String
    public let rank: Double
}
```

Extension 侧控制器：

```swift
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let repository: VaultRepository
    private let keyManager: MasterKeyManaging
    private let identityIndex: CredentialIdentityIndexing

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // 加载候选列表，只展示最小必要信息。
    }

    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        // 仅当最近已经解锁且策略允许时直接返回；否则取消并要求交互。
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        // 展示认证 UI，Face ID 成功后解密对应条目并 completeRequest。
    }
}
```

返回凭据时：

```swift
let credential = ASPasswordCredential(user: username, password: password)
extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
```

#### 3.4 自动填充安全策略

- Extension 只缓存候选索引，不缓存明文密码。
- 自动无交互填充默认关闭；只有“近期已解锁 + 用户启用低摩擦模式”才允许。
- 对银行、企业、支付类域名可强制二次认证。
- `ASCredentialIdentityStore` 中的用户名可能被系统用于显示，提供“隐私模式”：只显示账号别名，不显示真实用户名。
- 域名匹配必须 canonicalize，防止 `paypaI.com`、punycode、子域混淆。

---

## 阶段四：测试与安全审计 (Testing & Security Audit)

### 1. 必须覆盖的关键单元测试

#### 1.1 CryptoEngine

- AES-GCM 正常加解密。
- 错误 root key 解密失败。
- 修改 ciphertext 任意 bit 后解密失败。
- 修改 tag 后解密失败。
- 修改 AAD 后解密失败。
- 同一 item 多次加密 nonce 不重复。
- HKDF 对不同 itemID、purpose、vaultID 产生不同密钥。
- Envelope schema version 兼容旧版本。

#### 1.2 MasterKeyManager

- 首次创建 vault 生成高熵 root key 和恢复密钥。
- Secure Enclave 不可用时给出明确降级路径。
- Face ID 取消、失败、锁定时错误分类正确。
- 生物识别集变化导致密钥不可用时进入恢复流程。
- 解锁 session 超时后无法读取明文。
- root key rotation 后旧密文可迁移，新密文使用新 keyID。

#### 1.3 KeychainSecretStore

- 新增、读取、更新、删除成功。
- 重复写入返回 `duplicateItem` 或走 update 路径。
- 缺失 item 返回 `itemNotFound`。
- `errSecInteractionNotAllowed` 在后台或扩展无 UI 场景被正确处理。
- access group 配置错误时失败可诊断。
- Keychain value 被破坏后 envelope 解码失败且不会崩溃。

#### 1.4 SwiftData Metadata

- Group 父子关系与删除规则正确。
- Tag 多对多关系正确。
- 删除 group 不误删 item 密文。
- 删除 item 时 tombstone 与 pending sync 创建正确。
- schema migration 不丢失 `secretRef`。
- 高隐私模式不落盘敏感 metadata。

#### 1.5 CloudKit Sync

- 断网环境下本地操作进入 pending 队列。
- 恢复网络后按顺序重试并退避。
- CloudKit private database 未登录时不影响本地可用。
- `CKError.partialFailure`、quota exceeded、zone not found、user deleted zone 均有处理。
- 同一条目多设备并发编辑进入冲突队列。
- 远端密文篡改或 recordMAC 错误时拒绝导入。
- 用户 iCloud 加密数据重置时，本地缓存可重新上传或提示数据风险。

#### 1.6 Credential Provider Extension

- service identifier 精确匹配和子域匹配。
- punycode / Unicode 混淆域名测试。
- 无解锁 session 时必须交互认证。
- 认证取消不返回密码。
- Extension 时间预算内能加载候选。
- 隐私模式下不泄露真实用户名。

### 2. 安全审计清单

#### 2.1 威胁建模

- 使用 STRIDE 或 LINDDUN 建立威胁清单。
- 针对 CloudKit 泄露、设备丢失、恶意备份、调试日志泄露、剪贴板泄露、扩展滥用分别给出缓解措施。
- 明确不可防护边界：越狱设备、运行时注入、用户主动导出明文、屏幕拍摄。

#### 2.2 密码学审计

- 不自创加密算法。
- AES-GCM nonce 唯一性有测试保障。
- AAD 覆盖记录身份和 schema。
- recovery key 生成使用 CSPRNG。
- 人类主密码如果参与解密，KDF 必须单独审计。
- 密钥轮换和旧版本迁移有回滚方案。

#### 2.3 隐私审计

- 不把密码、域名、用户名写入日志。
- Crash report 过滤敏感字段。
- Analytics 默认关闭或只采集非敏感聚合事件。
- 剪贴板自动清理。
- 屏幕录制/截图提示和 App Switcher 遮罩。
- 导出文件必须再次加密并提醒用户保管。

### 3. Apple 审核防拒指南

#### 3.1 权限与能力声明

- `NSFaceIDUsageDescription` 必须清楚解释 Face ID 用于解锁本地保险库或确认自动填充。
- AutoFill Credential Provider entitlement 需要在主 App 和扩展同时开启。
- iCloud / CloudKit capability 需要解释同步用途。
- Keychain Sharing access group 仅限主 App 与官方扩展，不要扩大到无关 target。
- 如果使用通知提醒弱密码或泄露扫描，通知权限文案必须具体。

#### 3.2 隐私与数据安全

- 隐私政策必须说明：保存哪些数据、哪些数据仅在设备端处理、哪些密文会同步到 iCloud、开发者无法解密用户密码、用户如何删除数据。
- App Store 隐私标签需要准确描述 CloudKit 或自有服务器收集的数据类型。只在设备端处理且不出设备的数据通常不属于“收集”，但同步密文和账号信息需要按实际情况披露。
- 不要声称“绝对安全”“无法被破解”。应使用可验证表述，如“客户端加密”“云端不保存解密密钥”“开发者无法恢复主密钥”。
- 如果 App 提供账号体系或 Vapor 同步服务，必须提供删除账号与删除服务器数据路径。

#### 3.3 加密出口合规

- App Store Connect 仍需要回答加密使用问题。
- 如果只使用 Apple 操作系统内置加密能力，如 CryptoKit、Security、Keychain、CloudKit，通常不需要额外上传加密文档。
- 如果引入非 Apple 提供的标准算法实现，例如自研或第三方 Argon2id，可能需要根据销售地区和算法类型补充出口合规材料。
- 避免使用未公开、专有或自创密码算法，否则审核和合规成本显著增加。

#### 3.4 审核准备

- 提供完整可用版本，不提交占位 UI 或未完成扩展。
- 在 Review Notes 里说明如何开启 AutoFill、如何创建测试保险库、如何触发生物识别 fallback。
- 如果无法提供真实 demo account，提供本地 demo mode 和样例数据。
- 确保隐私政策、支持链接、营销截图与实际功能一致。
- 如果零知识架构导致“无法找回密码”，必须在新手引导中明确提示恢复密钥的重要性。

---

## 里程碑建议

### M1：安全内核原型

- 完成 `CryptoEngine`、`MasterKeyManager`、`SecretStore` mock 和真实 Keychain 实现。
- 单测覆盖密文篡改、AAD、Keychain 错误。
- 输出威胁模型 v1。

### M2：本地保险库

- 完成 SwiftData models。
- 完成 `VaultRepository` CRUD。
- 支持分组、标签、搜索 token。
- 支持本地锁定、解锁、恢复密钥。

### M3：CloudKit 零知识同步

- 完成 custom zone、record schema、pending 队列。
- 支持离线编辑、远端拉取、冲突保留。
- 支持新设备通过恢复密钥或可信设备导入。

### M4：SwiftUI 主 App

- 完成解锁页、仪表盘、分组/标签页、详情编辑页。
- 完成密码生成、剪贴板清理、隐私遮罩。
- 完成同步状态和冲突解决 UI。

### M5：系统自动填充

- 添加 Credential Provider Extension。
- 建立 identity index。
- 完成 Safari / 第三方 App 自动填充。
- 增加扩展专用安全测试。

### M6：审计与提交

- 完成单测、集成测试、真机测试。
- 完成隐私政策、App Store 隐私标签、加密出口合规问答。
- 准备 Review Notes、demo mode、恢复密钥说明。

---

## 官方资料参考

- [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit)
- [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- [Secure Enclave Keychain Token](https://developer.apple.com/documentation/security/ksecattrtokenidsecureenclave)
- [LocalAuthentication](https://developer.apple.com/documentation/localauthentication)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [CloudKit: Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)
- [ASCredentialProviderViewController](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller)
- [AutoFill Credential Provider Entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.authentication-services.autofill-credential-provider)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Export Compliance Documentation for Encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
