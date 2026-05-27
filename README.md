# PwdSafe — macOS 本地密码管理器

原生 macOS 密码管理器，本地优先，无云依赖，简洁实用。

## 技术栈

- **语言**: Swift 6
- **UI**: SwiftUI（NavigationSplitView 三栏布局）
- **存储**: JSON 文件持久化 + Apple Keychain 加密存储
- **加密**: AES-256-GCM（CryptoKit）+ VaultKey → ItemKey (HMAC-SHA256 派生)
- **认证**: LocalAuthentication（Touch ID / Apple Watch / 本机密码）
- **构建**: SPM + Xcode 26

## 功能

| 功能 | 说明 |
|------|------|
| 密码条目 CRUD | 标题、网址、用户名、邮箱、手机、密码、备注、分组、标签 |
| 加密存储 | VaultKey（Keychain 生物识别保护）→ ItemKey 每条目独立派生密钥 |
| 本机认证 | 查看/复制/编辑密码前需 Touch ID 或本机密码认证，支持 3 分钟免重复认证 |
| 密码生成器 | 可配置长度 (4-64)、字符类型，实时强度指示 |
| 密码历史 | 修改密码自动记录旧密码 SHA256 哈希，详情页可查看 |
| 分组/标签 | 创建、编辑、删除、混色，侧栏拖拽排序 |
| 搜索 | 标题、网址、用户名、备注、分组名、标签名模糊匹配 |
| 收藏夹 | 星标收藏，快速访问 |
| 回收站 | 软删除 → 恢复 / 永久删除，删除前需认证 |
| 加密备份 | 导出/导入 `.pwd` 加密备份文件（密码保护） |
| CSV 导出 | 明文导出 Title,Website,Username,Email,Phone,Password,Note,Group,Tags |
| 剪贴板清理 | 复制密码 30 秒自动清除（可配置） |
| 自动锁定 | 进入后台超时自动锁定（1/5/15 分钟 / 永不） |

## 架构

```
PwdSafeApp.swift          # App 入口 + ⌘N 快捷键
    └── VaultWindowView   # 主窗口（NavigationSplitView 三栏）
          ├── SidebarView        # 侧栏导航（全部/收藏/回收站/分组/标签）
          ├── ItemListView       # 条目列表 + 搜索 + 右键菜单
          └── ItemDetailView     # 详情（查看/复制/密码历史）
               └── ItemEditorView # 新建/编辑表单 + 密码生成器

VaultRepository          # 数据仓库（CRUD + 搜索 + 备份 + 锁定）
    ├── CryptoService    # AES-GCM 加密/解密
    ├── KeychainStore    # Keychain 读写（VaultKey + 密文）
    ├── AuthService      # LocalAuthentication 认证
    └── BackupService    # 加密备份(.pwd) + CSV 导出
```

## 数据模型

```
VaultItem ──secretRef──▶ Keychain(EncryptedSecret)
    │                        │
    ├── group: VaultGroup     │ AES-GCM 解密
    ├── tags: [VaultTag]      ▼
    └── metadata (JSON)   SecretPayload
                              ├── password
                              └── passwordHistory: [PasswordHistoryEntry]
```

## 开发

```bash
# 构建
swift build --disable-sandbox

# 测试
swift test --disable-sandbox

# Xcode
open PwdSafe.xcodeproj
```

**要求**: macOS 15.0+, Swift 6.0+, Xcode 26+

## 项目规模

| 指标 | 数值 |
|------|------|
| Swift 源文件 | 21 |
| 测试文件 | 3 |
| 总代码行数 | ~3,670 |
| 测试数量 | 88 (8 suites) |

## 安全设计

- 不存明文密码（Keychain 存 AES-GCM 密文）
- VaultKey 256-bit 随机生成，Keychain 生物识别保护
- 每条目独立派生 ItemKey（HMAC-SHA256），防跨条目解密
- AAD 绑定 itemID + version，防篡改和重放
- 认证会话 3 分钟超时，App 后台/锁屏自动清除
- 复制密码后剪贴板自动清空
- 删除先进回收站，清空前需认证