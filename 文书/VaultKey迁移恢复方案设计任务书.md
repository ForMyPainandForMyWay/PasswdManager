# VaultKey 迁移恢复方案设计任务书

## 一、现状与问题

### 1.1 当前架构

```
VaultKey = SymmetricKey.random()   // 纯随机 AES-256 密钥
    ↓
Keychain 存储: kSecAttrAccessibleWhenUnlockedThisDeviceOnly + .userPresence
    ↓
每个条目: itemKey = HMAC-SHA256(VaultKey, itemID)
    ↓
密文: EncryptedSecret { nonce, ciphertext, tag, keyID }  (AES-256-GCM)
    ↓
备份导出: EncryptedSecret 原样写入 .pwd 文件（不解密）
```

### 1.2 核心矛盾

- VaultKey 是**随机生成**、**设备绑定**（`ThisDeviceOnly`）、**不可导出**的。
- 备份文件 `.pwd` 中的 `EncryptedSecret` 绑定了当前设备的 VaultKey。
- 导入到其他 Mac / 重装系统后，VaultKey 不存在 → **所有密码无法解密**。
- CloudKit 同步（M4）同理：新设备拉到 `EncryptedSecret` 但无 VaultKey → 废数据。

**结论：当前备份实现了"密文可导出"，但未实现"密文可解密"，不具备真正的跨设备迁移能力。**

---

## 二、设计目标

### 2.1 覆盖场景

| 场景 | 说明 |
|------|------|
| 同设备日常解锁 | Touch ID → 本地 Keychain 加载 VaultKey，保持不变 |
| 跨设备 (同一 iCloud) | 新 Mac 自动从 iCloud Keychain 同步 VaultKey，零交互 |
| 跨设备 (无 iCloud) | 输入 Recovery Phrase 解包 VaultKey |
| 离线导入备份 | 导入 `.pwd` 文件，通过 Recovery Phrase 恢复解密能力 |
| CloudKit 同步 (M4) | 新设备通过 iCloud Keychain 自动获得 VaultKey，无缝解密 |

### 2.2 设计原则

1. **优先级回退**：iCloud Keychain 同步 → Recovery Phrase 解包 → 全新创建。
2. **最小改动**：复用现有 AES-GCM、Keychain、EncryptedSecret 结构体。
3. **日常零感知**：优先通道（本地/iCloud Keychain）成功时用户无感。
4. **单次输入**：Recovery Phrase 输入一次后，VaultKey 写入本地 + 同步 Keychain，后续无需再输。

---

## 三、架构设计

### 3.1 三级密钥加载链

```
┌─ Priority 1: 本地 Keychain (biometric 保护) ──────────────────┐
│  account:    "PwdSafe.VaultKey"                               │
│  access:     SecAccessControl(.userPresence) + ThisDeviceOnly │
│  同步:       否                                                │
│  用途:       日常 Touch ID 快速解锁（现有逻辑，不动）            │
└───────────────────────────────────────────────────────────────┘
                           ↓ 未找到
┌─ Priority 2: iCloud 同步 Keychain ────────────────────────────┐
│  account:    "PwdSafe.VaultKey.Sync"                          │
│  access:     kSecAttrSynchronizable + WhenUnlocked            │
│  accessCtrl: 无（.userPresence 与同步不兼容）                   │
│  同步:       是，通过 iCloud Keychain                          │
│  用途:       同 iCloud 账号下其他 Mac 已创建的 VaultKey          │
│  注意:       iCloud 端到端加密提供传输+存储保护                  │
│  成功后:     自动写入 Priority 1 本地 Keychain                  │
└───────────────────────────────────────────────────────────────┘
                           ↓ 未找到 (iCloud 未登录 / 首次使用)
┌─ Priority 3: Recovery Phrase 解包 ────────────────────────────┐
│  存储位置:   备份 .pwd 文件 / 本地 metadata / 云端 (M4)         │
│  存储格式:   WrappedVaultKey { salt, nonce, ciphertext, tag }  │
│  解密方式:   AES-GCM(WrappedVaultKey, key = HKDF(phrase, salt))│
│  用途:       用户输入 12 个 BIP39 助记词 → 解包 VaultKey        │
│  成功后:     同时写入 Priority 1 + Priority 2 Keychain          │
└───────────────────────────────────────────────────────────────┘
                           ↓ 都不存在
┌─ 全新创建 ─────────────────────────────────────────────────────┐
│  1. 随机生成 VaultKey (和现在一样)                              │
│  2. 随机生成 Recovery Phrase (BIP39, 12 词, 128-bit 熵)        │
│  3. 随机生成 salt (32 bytes)                                    │
│  4. WrappedVaultKey = AES-GCM(VaultKey, HKDF(phrase, salt))    │
│  5. 写入本地 Keychain + iCloud 同步 Keychain                    │
│  6. 一次性展示 Recovery Phrase 给用户，要求安全保存              │
└───────────────────────────────────────────────────────────────┘
```

### 3.2 为什么 iCloud Keychain 不加 `.userPresence`？

| 组合 | 结果 |
|------|------|
| `kSecAttrSynchronizable` + `SecAccessControl(.userPresence)` | 行为不确定，AC 对象可能无法正确序列化同步 |
| `kSecAttrSynchronizable` + `kSecAttrAccessibleWhenUnlocked`（无 AC） | 稳定同步，iCloud 端到端加密保障传输层安全 |

iCloud Keychain 的传输与存储本身使用端到端加密（设备密码 + 硬件安全密钥双重保护），足以替代 `.userPresence` 的防护。

---

## 四、数据结构设计

### 4.1 WrappedVaultKey（新增）

```swift
/// Recovery Phrase 加密后的 VaultKey，随备份和元数据一起存储
struct WrappedVaultKey: Codable, Sendable {
    var version: Int          // = 1
    var salt: Data            // 32 bytes, 随机, 用于 HKDF 派生 wrapping key
    var nonce: Data           // AES-GCM nonce, 12 bytes
    var ciphertext: Data      // 加密后的 VaultKey (32 bytes → 32 bytes + 16 tag)
    var tag: Data             // AES-GCM tag, 16 bytes
    var keyID: String         // SHA256(VaultKey).hex, 用于导入时校验密码正确性
}
```

### 4.2 BackupRecord（修改）

```swift
// 现有字段不变，新增一个可选字段
struct BackupRecord: Codable, Sendable {
    var version: Int
    var wrappedVaultKey: WrappedVaultKey?   // ← 新增: v1 备份无此字段, v2+ 携带
    var createdAt: Date
    var appVersion: String
    var items: [BackupItem]
    var groups: [BackupGroup]
    var tags: [BackupTag]
}
```

### 4.3 PersistedVaultData（修改）

```swift
// 本地元数据同样持久化 WrappedVaultKey
private struct PersistedVaultData: Codable {
    var wrappedVaultKey: WrappedVaultKey?   // ← 新增
    var items: [PersistedItem]
    var groups: [PersistedGroup]
    var tags: [PersistedTag]
}
```

### 4.4 EncryptedSecret（现有，不变）

```swift
// 已有 keyID 字段，可复用做 VaultKey 版本校验
struct EncryptedSecret: Codable, Sendable {
    var version: Int
    var algorithm: String      // "AES-256-GCM"
    var keyID: String          // SHA256(VaultKey).hex → 导入时比对
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}
```

---

## 五、各层改动清单

### 5.1 CryptoService 新增方法

```swift
protocol CryptoService: Sendable {
    // === 现有方法 (不变) ===
    func createVaultKey() throws -> SymmetricKey
    func encrypt(_ payload: SecretPayload, itemID: UUID, vaultKey: SymmetricKey) throws -> EncryptedSecret
    func decrypt(_ encrypted: EncryptedSecret, itemID: UUID, vaultKey: SymmetricKey) throws -> SecretPayload

    // === 新增: Recovery Phrase 相关 ===
    func generateRecoveryPhrase() -> String
    func generateSalt() -> Data
    func wrapVaultKey(_ key: SymmetricKey, phrase: String, salt: Data) throws -> WrappedVaultKey
    func unwrapVaultKey(_ wrapped: WrappedVaultKey, phrase: String) throws -> SymmetricKey
}
```

实现要点：
- `generateRecoveryPhrase()`: 按 BIP39 规范生成 12 个助记词（128-bit 熵）。
- `wrapVaultKey()`: `wrappingKey = HKDF-SHA256(phrase + "PwdSafe.Wrap", salt)` → `AES.GCM.seal(vaultKeyData, wrappingKey)`。
- `unwrapVaultKey()`: 逆向操作，解密后计算 `keyID == SHA256(decryptedKey).hex` 验证正确性。

### 5.2 KeychainStore 新增方法

```swift
protocol KeychainStore: Sendable {
    // === 现有方法 (不变) ===
    func vaultKeyExists() throws -> Bool
    func storeVaultKey(_ key: Data) throws
    func loadVaultKey() throws -> Data
    func deleteVaultKey() throws
    func storeSecret(_ data: Data, for secretRef: String) throws
    func loadSecret(for secretRef: String) throws -> Data
    func deleteSecret(for secretRef: String) throws

    // === 新增: iCloud 同步通道 ===
    func syncedVaultKeyExists() throws -> Bool
    func storeSyncedVaultKey(_ key: Data) throws
    func loadSyncedVaultKey() throws -> Data
    func deleteSyncedVaultKey() throws
}
```

实现要点：
- Account: `"PwdSafe.VaultKey.Sync"`
- Attributes: `kSecAttrSynchronizable = true`, `kSecAttrAccessible = kSecAttrAccessibleWhenUnlocked`
- 不设置 `SecAccessControl`（与同步不兼容）
- Service 名与本地 Keychain 共用 `"PwdSafe.Secret"`

### 5.3 VaultRepository 核心流程修改

#### 5.3.1 initializeVault() — 三级加载

```swift
func initializeVault() async throws {
    // Priority 1: 本地 biometric Keychain (现有逻辑)
    if let keyData = try? keychainStore.loadVaultKey() {
        vaultKey = SymmetricKey(data: keyData)
        isVaultReady = true
        updateSyncedCopy()  // 确保 iCloud 同步通道也有副本
        return
    }

    // Priority 2: iCloud 同步 Keychain
    if let syncData = try? keychainStore.loadSyncedVaultKey() {
        vaultKey = SymmetricKey(data: syncData)
        // 补充写入本地 biometric Keychain
        try? keychainStore.storeVaultKey(syncData)
        isVaultReady = true
        return
    }

    // Priority 3: Recovery Phrase 解包
    loadMetadata()
    if let wrapped = persistedWrappedVaultKey {
        // 返回 .recoveryRequired，由 UI 层展示 recovery 界面
        throw VaultError.recoveryRequired
    }

    // 全新创建
    let key = try cryptoService.createVaultKey()
    let phrase = cryptoService.generateRecoveryPhrase()
    let salt = cryptoService.generateSalt()
    let wrapped = try cryptoService.wrapVaultKey(key, phrase: phrase, salt: salt)

    persistedWrappedVaultKey = wrapped
    try keychainStore.storeVaultKey(key.withUnsafeBytes { Data($0) })
    try keychainStore.storeSyncedVaultKey(key.withUnsafeBytes { Data($0) })
    saveMetadata()
    vaultKey = key
    isVaultReady = true

    // 通过回调/状态将 recovery phrase 传给 UI 展示
    pendingRecoveryPhrase = phrase
}
```

#### 5.3.2 recoverWithPhrase(_:) — 手动恢复

```swift
func recoverWithPhrase(_ phrase: String) throws {
    guard let wrapped = persistedWrappedVaultKey else {
        throw VaultError.noWrappedKey
    }

    let key = try cryptoService.unwrapVaultKey(wrapped, phrase: phrase)
    let keyData = key.withUnsafeBytes { Data($0) }

    // 验证 keyID 匹配（用已有条目中的 EncryptedSecret.keyID 做校验）
    guard validateVaultKey(key) else {
        throw VaultError.invalidRecoveryPhrase
    }

    // 写入两级 Keychain
    try keychainStore.storeVaultKey(keyData)
    try keychainStore.storeSyncedVaultKey(keyData)

    vaultKey = key
    isVaultReady = true
}
```

#### 5.3.3 exportBackup() — 携带 WrappedVaultKey

```swift
func exportBackup() async throws -> BackupRecord {
    try await authService.authenticate(reason: "导出加密备份", scope: .destructive)
    var record = try BackupService.exportBackup(...)
    record.wrappedVaultKey = persistedWrappedVaultKey  // ← 新增
    return record
}
```

#### 5.3.4 importBackup(from:) — 处理 WrappedVaultKey

```swift
func importBackup(from url: URL) async throws {
    let record = try BackupService.readBackup(from: url)

    // 如果备份携带 WrappedVaultKey 而本地没有，自动保存
    if let wrapped = record.wrappedVaultKey, persistedWrappedVaultKey == nil {
        persistedWrappedVaultKey = wrapped
        saveMetadata()
    }

    try await BackupService.importBackup(record, into: self)
}
```

#### 5.3.5 新增 VaultError 类型

```swift
enum VaultError: Error {
    case notInitialized
    case itemNotFound
    case recoveryRequired       // ← 新增: 需要输入 Recovery Phrase
    case noWrappedKey           // ← 新增: 没有加密的 VaultKey 可解
    case invalidRecoveryPhrase  // ← 新增: Recovery Phrase 不正确
}
```

### 5.4 UI 层新增

| 组件 | 说明 |
|------|------|
| `RecoveryView` | 新建保险库后展示 12 个助记词，引导用户安全保存 |
| `RecoveryInputView` | 保险库初始化时检测到 `recoveryRequired`，提供助记词输入框 |
| 设置页入口 | "查看 Recovery Phrase"（需重新认证）、"导出 Recovery Phrase" |

### 5.5 BackupService 兼容性

- v1 备份（无 `wrappedVaultKey` 字段）：解码为 `nil`，导入后若本地无 VaultKey 则触发 `recoveryRequired`。
- v2 备份（含 `wrappedVaultKey`）：导入时自动存储，配合 Recovery Phrase 可解。
- `BackupService.currentVersion` 升级为 2。

---

## 六、各场景验证矩阵

| # | 场景 | 前置条件 | 预期行为 |
|---|------|---------|---------|
| 1 | 同设备日常解锁 | VaultKey 在本地 Keychain | Touch ID → 直接加载 VaultKey，无感 |
| 2 | 同 iCloud 新 Mac 首次启动 | VaultKey 在 iCloud Keychain | 自动同步 VaultKey → 写入本地 Keychain → 正常使用 |
| 3 | 新 Mac + 无 iCloud + 有备份 | 用户持有 Recovery Phrase + .pwd 文件 | 导入备份 → 输入 Recovery Phrase → 解包 VaultKey → 解密所有条目 |
| 4 | 新 Mac + 无 iCloud + 无备份 | 用户持有 Recovery Phrase | Recovery 界面输入 → 解包 VaultKey → 保险库为空但已可操作 |
| 5 | 错误 Recovery Phrase | — | 显示错误提示，keyID 校验不通过 |
| 6 | 导出的 v2 备份在另一台 Mac 恢复 | 另一台 Mac 已通过 iCloud 获得 VaultKey | 导入后无需额外操作，直接可解密 |
| 7 | iCloud 未登录时导出 | — | 本地 Keychain 正常，导出携带 WrappedVaultKey |
| 8 | iCloud 未登录时新建保险库 | — | iCloud 同步 Keychain 写入静默失败（由 Keychain API 自行处理） |
| 9 | CloudKit 同步 (M4 追加) | iCloud Keychain 已同步 VaultKey | 云端的 EncryptedSecret 自动可解密 |

---

## 七、安全性分析

| 攻击面 | 防护措施 |
|--------|---------|
| Recovery Phrase 泄露 | BIP39 12 词 = 128-bit 熵，约 3.4×10³⁸ 种组合，暴力不可行 |
| iCloud Keychain 窃取 | 端到端加密，Apple 无解密能力 |
| 备份文件被窃 | `EncryptedSecret` 仍是 AES-256-GCM，无 VaultKey 不可解 |
| WrappedVaultKey 被窃 | 需要 Recovery Phrase 才能解包，HKDF + AES-GCM 双层保护 |
| 本地 Keychain 入侵 | `SecAccessControl(.userPresence)` 禁止无生物认证的读取 |
| Recovery Phrase 丢失 | 唯一故障点 → UI 定期提醒确认备份；用户需自行承担保管责任 |

---

## 八、实施计划

### M4 前置准备 (当前阶段)

| 步骤 | 说明 | 优先级 |
|------|------|--------|
| 1 | CryptoService 新增 BIP39 生成、wrap/unwrap VaultKey 方法 | P0 |
| 2 | KeychainStore 新增 iCloud 同步通道读写方法 | P0 |
| 3 | SecretTypes 新增 WrappedVaultKey 结构体 | P0 |
| 4 | VaultRepository 实现三级密钥加载链 + recoverWithPhrase | P0 |
| 5 | BackupRecord 升级 v2，携带 WrappedVaultKey | P0 |
| 6 | PersistedVaultData 新增 wrappedVaultKey 持久化 | P0 |
| 7 | RecoveryView / RecoveryInputView 界面 | P1 |
| 8 | 设置页 Recovery Phrase 查看/导出入口 | P1 |
| 9 | 测试用例编写（验证矩阵全部场景） | P0 |

### M4 (CloudKit 同步叠加)

M4 实施 CloudKit 同步时，VaultKey 分发已通过本方案解决：
- 同 iCloud → Priority 2 自动同步（零改动）
- 不同 iCloud / 离线 → 通过恢复界面同步（已实现）

CloudKit 层只需关注 `EncryptedSecret` 的上传/下拉/冲突三件事。

---

## 九、备选与废弃方案

### 9.1 废弃：纯 Master Password 派生 (方案 A)

- 缺点：需要用户每次记住主密码，与当前 Touch ID 无缝体验相悖。
- 保留价值：若未来支持"主密码 + Touch ID 缓存"模式，可叠加。

### 9.2 废弃：仅 iCloud Keychain 同步 (方案 B)

- 缺点：依赖 Apple 生态，无 iCloud 用户无法迁移；备份文件跨平台不可用。
- 缺点：Keychain 同步偶有延迟/失败，无兜底机制。

### 9.3 废弃：仅 Recovery Key (方案 C)

- 缺点：所有跨设备场景都要输入 Recovery Phrase，体验不如自动同步。
- 按本方案作为 Priority 3 保留。

---

## 十、总结

本方案通过 **"iCloud Keychain 自动同步 (Priority 2) + Recovery Phrase 手动解包 (Priority 3)"** 的双通道设计，在不破坏现有 Touch ID 无缝体验的前提下，解决了 VaultKey 跨设备迁移的痛点。

- 对同 iCloud 的用户：**零感知**，VaultKey 自动跟随设备。
- 对离线/跨平台用户：输入一次 Recovery Phrase，后续同样**零感知**。
- 对开发者：改动集中在 CryptoService / KeychainStore / VaultRepository 三层，且完全向前兼容 v1 备份格式。
