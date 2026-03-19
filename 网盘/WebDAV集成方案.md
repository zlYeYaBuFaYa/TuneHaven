# 方案 C：WebDAV 协议接入方案

> 版本：v1.1（修正版）  
> 日期：2026-03-19  
> 状态：待开发

---

## 一、需求概述

在 TuneHaven 中新增 **WebDAV 协议导入** 功能，实现：

1. 用户在 App 内配置 WebDAV 服务器地址和凭据（支持多账户）
2. 在 App 内浏览远程目录结构，仅展示文件夹和音频文件
3. 支持多选音频文件并下载到本地
4. 下载完成后走现有 ImportService 导入流程
5. 凭据安全存储，支持连接测试

### 1.1 适用场景

| 场景 | 说明 |
|------|------|
| 坚果云 | 国内最友好的 WebDAV 服务（原生支持，免费 1GB/月流量） |
| Alist | 开源网盘聚合工具，可将百度网盘、阿里云盘等桥接为 WebDAV |
| 群晖 NAS | Synology WebDAV Server 套件 |
| InfiniCLOUD | 日本 TeraCloud 提供的免费 WebDAV 云存储 |
| Nextcloud / ownCloud | 自建云盘，原生 WebDAV |
| Box / 4shared 等 | 部分海外网盘支持 WebDAV |

> **重要说明**：百度网盘官方**不支持** WebDAV，需通过 Alist 等第三方工具桥接后才能以 WebDAV 方式访问。方案中应在 UI 上对此做明确提示。

---

## 二、WebDAV 协议概述

### 2.1 核心方法

WebDAV 基于 HTTP 扩展，本方案涉及的方法：

| HTTP 方法 | 用途 | 说明 |
|-----------|------|------|
| `PROPFIND` | 列出目录内容 | Depth: 1 获取直接子项属性 |
| `GET` | 下载文件 | 支持 Range 断点续传 |
| `HEAD` | 获取文件信息 | 检查文件大小、是否存在 |
| `OPTIONS` | 探测服务器能力 | 用于连接测试 |

### 2.2 认证方式

| 方式 | 说明 | 支持情况 |
|------|------|---------|
| Basic Auth | 用户名 + 密码，base64 编码 | ✅ 必须支持 |
| Digest Auth | 挑战-应答模式，更安全 | ✅ URLSession 原生支持 |
| Bearer Token | OAuth 令牌（部分服务商） | ❌ 暂不支持 |
| 无认证 | 公开目录 | ✅ 支持 |

### 2.3 PROPFIND 请求/响应示例

请求：

```http
PROPFIND /dav/Music/ HTTP/1.1
Host: dav.example.com
Depth: 1
Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getcontenttype/>
    <d:getlastmodified/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>
```

响应为 `207 Multi-Status` XML，包含每个资源的属性。

---

## 三、架构设计

### 3.1 分层架构

严格遵循项目 Clean Architecture 分层：

```
Core Layer（基础设施）
├── WebDAVClient.swift            # WebDAV 协议客户端（PROPFIND/GET/OPTIONS）
├── WebDAVXMLParser.swift         # PROPFIND 响应 XML 解析
├── WebDAVSessionDelegate.swift   # URLSession 代理（自签证书 + Digest Auth）
└── KeychainHelper.swift          # 通用 Keychain 封装（方案 A/C 共享）

Domain Layer（领域层）
├── WebDAVAccount.swift         # 账户实体（服务器配置）
├── WebDAVFile.swift            # 远程文件实体
└── WebDAVService.swift         # 业务服务（浏览 + 下载 + 导入）

Data Layer（数据层）
└── WebDAVAccountStore.swift    # 账户持久化（Keychain 凭据 + UserDefaults 元信息）

Presentation Layer（表现层）
├── WebDAVAccountListView.swift # 账户列表（多账户管理）
├── WebDAVAccountEditView.swift # 添加/编辑账户
├── WebDAVBrowserView.swift     # 文件浏览器
└── WebDAVDownloadView.swift    # 下载进度 + 导入结果
```

### 3.2 文件清单

#### 新增文件（11 个）

| 文件路径 | 层级 | 职责 |
|---------|------|------|
| `Core/Network/WebDAVClient.swift` | Core | WebDAV HTTP 请求封装（PROPFIND、GET、OPTIONS、HEAD），支持 Basic/Digest Auth |
| `Core/Network/WebDAVXMLParser.swift` | Core | 解析 PROPFIND 207 Multi-Status XML 响应为结构化数据 |
| `Core/Network/WebDAVSessionDelegate.swift` | Core | URLSession 代理，处理自签证书信任和 Digest Auth 挑战 |
| `Core/Utils/KeychainHelper.swift` | Core | 通用 Keychain 读写封装（方案 A/C 共享基础设施） |
| `Domain/Entities/WebDAVAccount.swift` | Domain | 账户实体定义（服务器 URL、端口、路径、显示名） |
| `Domain/Entities/WebDAVFile.swift` | Domain | 远程文件实体（路径、大小、类型、修改时间） |
| `Domain/Services/WebDAVService.swift` | Domain | 业务逻辑：连接测试、目录浏览、音频筛选、下载队列、导入衔接 |
| `Data/WebDAVAccountStore.swift` | Data | 账户配置持久化（KeychainHelper + UserDefaults） |
| `Presentation/Import/WebDAV/WebDAVAccountListView.swift` | Presentation | 账户列表 + 添加/删除/编辑入口 |
| `Presentation/Import/WebDAV/WebDAVAccountEditView.swift` | Presentation | 添加/编辑账户表单（Sheet 呈现） |
| `Presentation/Import/WebDAV/WebDAVBrowserView.swift` | Presentation | 远程文件浏览器 UI：目录导航 + 音频筛选 + 多选 |
| `Presentation/Import/WebDAV/WebDAVDownloadView.swift` | Presentation | 下载进度 + 导入结果展示 |

#### 修改文件（4 个）

| 文件路径 | 改动说明 |
|---------|---------|
| `Presentation/Settings/SettingsImportSection.swift` | 新增"WebDAV 导入"入口 |
| `App/TuneHavenApp.swift` | 注入 WebDAVService |
| `App/AppError.swift` | 新增 WebDAV 相关错误码（DAV001 ~ DAV005） |
| `Presentation/Import/CloudDriveImportView.swift` | 可选：在云盘导入页增加 WebDAV 入口 |

---

## 四、核心流程设计

### 4.1 账户配置流程

```
设置 → 导入音乐 → WebDAV 导入
  │
  ├── 已有账户 → 显示账户列表
  │     ├── 点击账户 → 进入文件浏览器
  │     ├── 长按/左滑 → 编辑 / 删除
  │     └── 点击"+" → 添加新账户
  │
  └── 无账户 → 显示空状态 + "添加 WebDAV 账户"按钮
        │
        └── WebDAVAccountEditView
              1. 输入服务器地址（如 https://dav.jianguoyun.com/dav/）
              2. 输入用户名
              3. 输入密码（或应用专用密码）
              4. 可选：自定义显示名称（默认取域名）
              5. 可选：信任自签证书开关
              6. 点击"测试连接"
                   → OPTIONS 请求检测 WebDAV 支持
                   → PROPFIND / 请求验证凭据
                   → 成功: 提示"连接成功"，启用保存按钮
                   → 失败: 显示具体错误原因
              7. 保存 → 凭据存 Keychain，元信息存 UserDefaults
```

### 4.2 文件浏览流程

```
WebDAVBrowserView（NavigationStack 内嵌）
  │
  ├── 加载目录内容
  │     PROPFIND {baseURL}{currentPath}
  │       Depth: 1
  │     → 解析 XML 获取子项列表
  │     → 过滤：仅保留目录 + 音频文件（按扩展名白名单匹配）
  │     → 排序：目录在前，文件在后，各自按名称排序
  │
  ├── UI 展示
  │     ┌────────────────────────────────────┐
  │     │ ← 坚果云        /Music/           │ ← 导航栏（账户名 + 当前路径）
  │     ├────────────────────────────────────┤
  │     │ 📁 古典音乐                        │ ← 目录（点击进入子目录）
  │     │ 📁 流行                            │
  │     │ ☐ 🎵 歌曲A.mp3        4.2 MB     │ ← 音频文件（可勾选）
  │     │ ☐ 🎵 歌曲B.flac      28.1 MB     │
  │     │ ☑ 🎵 歌曲C.m4a        5.7 MB     │ ← 已选中
  │     ├────────────────────────────────────┤
  │     │ 已选 1 首  33.8 MB     [下载导入]  │ ← 底部操作栏（显示文件数 + 总大小）
  │     └────────────────────────────────────┘
  │
  ├── 点击目录 → push 进入子目录（NavigationLink）
  ├── 勾选/取消勾选音频文件 → 更新已选列表
  │     选中状态**跨目录保持**（切换目录不丢失已选项）
  ├── 支持"全选当前目录音频"快捷操作
  ├── 点击"下载导入" → 跳转到 WebDAVDownloadView
  └── 空目录 → EmptyStateView（"此目录下没有音频文件"）
```

### 4.3 下载与导入流程

```
WebDAVDownloadView
  │
  ├── 逐文件处理（串行下载，避免连接过多被服务器拒绝）：
  │
  │     1. HEAD 请求确认文件大小（校验 <= 500MB）
  │         → 超限: 记录 skippedOversize，跳过
  │
  │     2. GET 请求下载文件
  │         URLSession downloadTask
  │         → 下载到 tmp/import_temp/{原始文件名}
  │         → 实时更新下载进度（bytesReceived / totalBytes）
  │         → 支持 Range 断点续传（网络中断重连时从断点继续）
  │
  │     3. 下载完成 → 加入待导入列表
  │     4. 下载失败 / 超时（5 分钟） → 记录失败，可选重试，继续下一个
  │
  ├── 全部下载完成 → 批量调用 ImportService.importFromFiles(urls:)
  │     → 复用现有导入逻辑（SHA256 去重、元数据解析、复制到 Music 目录）
  │     → 清理 tmp/import_temp/ 中的临时文件
  │
  └── 展示综合结果
        ┌────────────────────────────────────┐
        │            导入结果                 │
        ├────────────────────────────────────┤
        │ ✅ 成功导入              3 首      │
        │ ⏭️ 已跳过（重复）        1 首      │
        │ ⬇️ 下载失败              0 首      │
        │ 📦 文件过大（已跳过）    0 首      │
        ├────────────────────────────────────┤
        │           [完成]                   │
        └────────────────────────────────────┘
```

### 4.4 连接测试流程

```
用户点击"测试连接"
  │
  1. 校验 URL 格式（必须为 http:// 或 https://）
  │
  2. OPTIONS 请求检测 WebDAV 支持
  │     → 检查响应 Header 中的 DAV: 字段
  │     → 检查 Allow: 字段包含 PROPFIND
  │     → 失败: "服务器不支持 WebDAV 协议"
  │
  3. PROPFIND / 请求验证凭据
  │     Depth: 0（仅请求根属性，不列出内容，最轻量）
  │     → 200/207: 验证通过
  │     → 401: "用户名或密码错误"
  │     → 403: "无权访问，请检查权限"
  │     → 404: "路径不存在，请检查服务器地址"
  │     → SSL 错误: "证书验证失败，可开启'信任自签证书'选项"
  │     → 超时(10s): "连接超时，请检查网络和服务器地址"
  │
  4. 显示结果（成功/失败 + 错误原因）
```

---

## 五、数据模型

### 5.1 WebDAVAccount（账户配置）

```swift
struct WebDAVAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String          // 显示名称（如"坚果云"、"家里 NAS"）
    var serverURL: String            // 完整 URL（如 https://dav.jianguoyun.com/dav/）
    var username: String             // 用户名
    // password 存储在 Keychain，不存 UserDefaults
    var trustSelfSignedCert: Bool    // 是否信任自签证书
    var createdAt: Date
    var lastConnectedAt: Date?       // 上次成功连接时间

    var host: String { URL(string: serverURL)?.host ?? serverURL }
}
```

### 5.2 WebDAVFile（远程文件实体）

```swift
struct WebDAVFile: Identifiable, Hashable {
    let href: String                 // 完整路径（URL 编码，中文路径需 removingPercentEncoding 显示）
    let displayName: String          // 显示名称
    let contentLength: Int64         // 文件大小（字节），目录为 0
    let contentType: String?         // MIME 类型
    let lastModified: Date?          // 最后修改时间
    let isDirectory: Bool            // 是否为目录
    let etag: String?                // ETag（用于缓存校验）

    var id: String { href }

    /// 音频格式白名单（Domain 层自持，不依赖 Core 层 FileStorageService）
    /// 与 FileStorageService.supportedExtensions 保持一致
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "alac", "wav", "flac", "aiff", "aif", "caf"
    ]

    var isAudio: Bool {
        guard !isDirectory else { return false }
        let ext = (fileName as NSString).pathExtension.lowercased()
        return Self.audioExtensions.contains(ext)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file)
    }

    /// 显示用文件名（优先 displayName，降级从 href 解码提取）
    var fileName: String {
        if !displayName.isEmpty { return displayName }
        let last = (href as NSString).lastPathComponent
        return last.removingPercentEncoding ?? last
    }
}
```

> **设计决策**：`audioExtensions` 定义在 Domain 层实体上而非引用 Core 层的 `FileStorageService.supportedExtensions`，避免违反 Clean Architecture 的依赖方向（Domain 不可依赖 Core）。两处需人工保持同步，新增格式时需同时更新。

### 5.3 WebDAVDownloadTask（下载任务状态）

```swift
struct WebDAVDownloadTask: Identifiable {
    let id: UUID
    let file: WebDAVFile
    var status: DownloadStatus
    var bytesReceived: Int64
    var totalBytes: Int64
    var error: String?

    enum DownloadStatus {
        case waiting
        case downloading
        case completed(localURL: URL)
        case failed
        case skippedOversize
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }
}
```

### 5.4 WebDAVImportResult（导入综合结果）

```swift
struct WebDAVImportResult {
    let downloadedCount: Int         // 下载成功数
    let downloadFailedCount: Int     // 下载失败数
    let skippedOversizeCount: Int    // 超大小跳过数
    let importResult: ImportResult?  // 复用现有 ImportResult（含成功/重复/格式/失败明细）
    let errors: [String]             // 下载失败的错误信息列表

    var totalSelected: Int {
        downloadedCount + downloadFailedCount + skippedOversizeCount
    }
}
```

---

## 六、核心组件设计

### 6.1 WebDAVClient

```swift
actor WebDAVClient {
    struct Configuration {
        let baseURL: URL
        let username: String
        let password: String
        let trustSelfSignedCert: Bool
        let timeoutInterval: TimeInterval  // 默认 30s
    }

    init(configuration: Configuration)

    /// 连接测试：OPTIONS + PROPFIND Depth:0
    func testConnection() async throws -> Bool

    /// 列出目录内容
    /// - Parameter path: 相对于 baseURL 的路径（如 "/Music/"）
    /// - Returns: 目录下的文件和子目录列表
    func listDirectory(path: String) async throws -> [WebDAVFile]

    /// 下载文件到本地临时目录
    /// - Parameters:
    ///   - remotePath: 远程文件路径
    ///   - destination: 本地目标路径
    ///   - progress: 进度回调 (bytesReceived, totalBytes)
    func downloadFile(
        remotePath: String,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL

    /// 获取文件信息（HEAD 请求）
    func fileInfo(path: String) async throws -> (size: Int64, etag: String?)
}
```

**实现要点：**

- 使用 `URLSession` 原生能力，不引入第三方依赖
- Basic Auth 通过 `Authorization` Header 手动构造（`Basic base64(user:pass)`）
- Digest Auth 由 `URLSession` 的 `URLAuthenticationChallenge` 自动处理
- XML 解析使用系统 `XMLParser`（Foundation 内置）
- **中文路径处理**：构造 PROPFIND 请求时，路径需经过 `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` 编码；解析响应的 `<d:href>` 时需 `removingPercentEncoding` 还原显示名
- **取消机制**：内部持有 `URLSessionDownloadTask` 引用，`cancelDownload()` 时调用 `task.cancel()` 并设置取消标记

**actor 与 URLSessionDelegate 的关系：**

`actor` 不能继承 `NSObject`，因此 `URLSessionDelegate`（含自签证书信任、Digest Auth 挑战）需拆为独立类：

```swift
final class WebDAVSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    var trustSelfSignedCert: Bool = false

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           trustSelfSignedCert,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
```

`WebDAVClient` actor 内部持有此 delegate 并创建对应的 `URLSession`。

### 6.2 WebDAVXMLParser

```swift
final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    /// 解析 PROPFIND 207 Multi-Status 响应体
    /// - Parameters:
    ///   - data: XML 响应数据
    ///   - requestPath: 发起 PROPFIND 的路径（用于过滤父目录条目）
    /// - Returns: 解析出的文件列表（不含父目录自身）
    static func parseMultiStatus(_ data: Data, requestPath: String) throws -> [WebDAVFile]
}
```

> **重要**：PROPFIND `Depth: 1` 的响应中，第一个 `<d:response>` 是**被请求目录自身**而非子项。解析时必须过滤掉 `href` 与 `requestPath` 相同（或经 URL 解码后相同）的条目，否则目录列表中会多出一个代表"当前目录"的错误条目。

**解析的 XML 元素：**

| DAV 属性 | 映射字段 | 说明 |
|----------|---------|------|
| `<d:href>` | href | 资源路径 |
| `<d:displayname>` | displayName | 显示名称 |
| `<d:getcontentlength>` | contentLength | 文件大小 |
| `<d:getcontenttype>` | contentType | MIME 类型 |
| `<d:getlastmodified>` | lastModified | 修改时间 |
| `<d:resourcetype><d:collection/>` | isDirectory | 是否为目录 |
| `<d:getetag>` | etag | ETag |

### 6.3 WebDAVAccountStore

```swift
final class WebDAVAccountStore {
    static let shared = WebDAVAccountStore()

    /// 获取所有已保存账户（不含密码）
    func loadAccounts() -> [WebDAVAccount]

    /// 保存账户配置（密码存 Keychain，其余存 UserDefaults）
    func saveAccount(_ account: WebDAVAccount, password: String) throws

    /// 删除账户（同时清除 Keychain 中的密码）
    func deleteAccount(id: UUID) throws

    /// 获取账户密码（从 Keychain 读取）
    func password(for accountId: UUID) -> String?

    /// 更新最后连接时间
    func updateLastConnected(accountId: UUID)
}
```

**存储方案：**

| 数据 | 存储位置 | 说明 |
|------|---------|------|
| 账户列表（不含密码） | UserDefaults `webdav_accounts` | JSON 数组 |
| 账户密码 | Keychain `webdav_pwd_{accountId}` | 加密存储 |

### 6.4 WebDAVService

```swift
@MainActor
final class WebDAVService: ObservableObject {
    @Published private(set) var accounts: [WebDAVAccount] = []
    @Published private(set) var currentFiles: [WebDAVFile] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var downloadTasks: [WebDAVDownloadTask] = []
    @Published private(set) var overallProgress: Double = 0

    private let accountStore: WebDAVAccountStore
    private var activeClient: WebDAVClient?

    // 账户管理
    func loadAccounts()
    func addAccount(_ account: WebDAVAccount, password: String) async throws
    func deleteAccount(id: UUID) throws
    func testConnection(account: WebDAVAccount, password: String) async throws -> Bool

    // 文件浏览
    func connect(to account: WebDAVAccount) async throws   // 建立连接 + 加载根目录
    func loadDirectory(_ path: String) async throws        // 加载指定目录
    func disconnect()                                       // 断开当前连接

    // 下载与导入
    func downloadAndImport(
        files: [WebDAVFile],
        account: WebDAVAccount,
        importService: ImportService,
        onProgress: @escaping @MainActor (WebDAVDownloadTask) -> Void
    ) async -> WebDAVImportResult

    func cancelDownload()
}
```

---

## 七、错误处理

### 7.1 新增错误码

| 错误码 | 枚举值 | 触发场景 |
|--------|--------|---------|
| DAV001 | `webdavConnectionFailed(String)` | 连接失败（网络不可达、DNS 解析失败、超时等） |
| DAV002 | `webdavAuthFailed` | 认证失败（401 Unauthorized） |
| DAV003 | `webdavServerNotSupported` | 服务器不支持 WebDAV 协议 |
| DAV004 | `webdavDownloadFailed(String)` | 文件下载失败（含文件名） |
| DAV005 | `webdavCertificateError` | SSL 证书验证失败 |

### 7.2 错误处理策略

| 场景 | 处理方式 |
|------|---------|
| 连接超时（30s） | Toast 提示"连接超时"，建议检查服务器地址和网络 |
| 401 认证失败 | Toast 提示"用户名或密码错误"，引导重新编辑账户 |
| SSL 证书错误 | 提示可开启"信任自签证书"选项 |
| 目录加载失败 | 显示错误 + 重试按钮 |
| 单文件下载失败 | 记录失败原因，跳过继续下一个，最终汇总展示 |
| 单文件下载超时（5 分钟） | 同上，标记为超时失败 |
| 服务器不支持 WebDAV | OPTIONS 检测，提示"该服务器不支持 WebDAV" |
| 存储空间不足 | 捕获写入错误，提示 storageFull |

---

## 八、持久化方案

### 8.1 Keychain 存储（安全数据）

通过通用的 `KeychainHelper`（位于 `Core/Utils/KeychainHelper.swift`）封装 Security.framework 的 Keychain 操作。该 Helper 也可被方案 A（百度 Open API 的 Token 存储）复用。

```swift
enum KeychainHelper {
    static func save(_ data: Data, forKey key: String) throws
    static func load(forKey key: String) -> Data?
    static func delete(forKey key: String)

    static func saveString(_ string: String, forKey key: String) throws
    static func loadString(forKey key: String) -> String?
}
```

| Key 模式 | 类型 | 说明 |
|----------|------|------|
| `webdav_pwd_{accountId}` | String | 账户密码 |

### 8.2 UserDefaults 存储（非敏感数据）

| Key | 类型 | 说明 |
|-----|------|------|
| `webdav_accounts` | Data (JSON) | 账户配置列表（WebDAVAccount 数组的 JSON 编码） |

---

## 九、UI 设计

### 9.1 账户列表页（WebDAVAccountListView）

```
┌────────────────────────────────────┐
│ ← WebDAV 导入                 [+] │ ← 导航栏
├────────────────────────────────────┤
│  WebDAV 服务器                     │ ← Section Header
├────────────────────────────────────┤
│  🌐 坚果云                        │
│     dav.jianguoyun.com             │
│     上次连接: 3 分钟前         >   │
├────────────────────────────────────┤
│  🖥️ 家里 NAS                      │
│     192.168.1.100:5005             │
│     上次连接: 2 天前           >   │
├────────────────────────────────────┤
│                                    │
│  使用说明                          │ ← Section Header
├────────────────────────────────────┤
│  1. 点击 [+] 添加 WebDAV 服务器   │
│  2. 输入服务器地址和登录凭据       │
│  3. 测试连接成功后保存             │
│  4. 点击已添加的服务器浏览和导入   │
├────────────────────────────────────┤
│  ⚠️ 百度网盘不支持 WebDAV，       │
│  需通过 Alist 等工具桥接后使用     │
└────────────────────────────────────┘
```

### 9.2 账户编辑页（Sheet: WebDAVAccountEditView）

```
┌────────────────────────────────────┐
│  取消      添加 WebDAV     保存    │ ← 导航栏（保存按钮初始禁用）
├────────────────────────────────────┤
│  服务器配置                        │
├────────────────────────────────────┤
│  显示名称     [坚果云           ]  │ ← 可选，空则取域名
│  服务器地址   [https://dav.jian ]  │ ← 必填
│  用户名       [user@example.com ]  │ ← 必填
│  密码         [••••••••••       ]  │ ← 必填
├────────────────────────────────────┤
│  高级选项                          │
├────────────────────────────────────┤
│  信任自签证书      [ 🔘 ]          │ ← Toggle
├────────────────────────────────────┤
│  [       测试连接       ]          │ ← 按钮
│  ✅ 连接成功                       │ ← 测试结果
├────────────────────────────────────┤
│  常用 WebDAV 地址                  │
├────────────────────────────────────┤
│  坚果云  https://dav.jianguoyun.com/dav/     │ ← 点击自动填充
│  Alist   http://IP:5244/dav/                 │
│  群晖    https://IP:5006/                    │
│  InfiniCLOUD  https://xxx.teracloud.jp/dav/  │
└────────────────────────────────────┘
```

### 9.3 文件浏览器（WebDAVBrowserView）

同第四节 4.2 中的 UI 描述。

### 9.4 下载进度页（WebDAVDownloadView）

```
┌────────────────────────────────────┐
│  下载与导入                        │
├────────────────────────────────────┤
│  整体进度                          │
│  ████████████░░░░  75%   3/4      │
├────────────────────────────────────┤
│  ✅ 歌曲A.mp3          4.2 MB     │ ← 已完成
│  ✅ 歌曲B.flac         28.1 MB     │ ← 已完成
│  ⬇️ 歌曲C.m4a          5.7 MB     │ ← 下载中
│     ████████░░░  62%  3.5 MB/s    │
│  ⏳ 歌曲D.wav          42.0 MB     │ ← 等待中
├────────────────────────────────────┤
│  [       取消       ]              │
└────────────────────────────────────┘
```

---

## 十、设置页集成

在 SettingsImportSection 中新增 WebDAV 入口：

```
┌────────────────────────────────────┐
│  导入音乐                          │
├────────────────────────────────────┤
│  📂 文件导入                   >   │
│  🎵 从 Apple Music 资料库导入  >   │
│  ☁️ 云盘导入                   >   │
│  📶 WiFi 传输                  >   │
│  🌐 WebDAV 导入                >   │  ← 新增
└────────────────────────────────────┘
```

---

## 十一、依赖注入

在 `TuneHavenApp.swift` 中新增（与现有 Service 保持一致的 `@StateObject` 模式）：

```swift
@StateObject private var webDAVService = WebDAVService()

// 注入 SwiftUI 环境（在 RootTabView 上）
.environmentObject(webDAVService)
```

---

## 十二、安全考量

### 12.1 凭据安全

| 措施 | 说明 |
|------|------|
| Keychain 存储密码 | 利用 iOS 硬件加密，App 卸载后自动清除 |
| 不存储明文密码到 UserDefaults | UserDefaults 仅存非敏感的账户元信息 |
| Basic Auth 仅在 HTTPS 下使用 | HTTP 场景下 UI 警告"数据将以明文传输" |

### 12.2 自签证书处理

- 默认不信任自签证书（遵循系统 TLS 验证）
- 用户可在账户设置中手动开启"信任自签证书"
- 仅对该账户的请求生效，不影响其他网络请求
- 实现方式：自定义 `URLSessionDelegate`，在 `didReceive challenge` 中检查账户配置

### 12.3 网络安全提示

- HTTP（非 HTTPS）连接时，在账户编辑页显示安全警告
- 提示文案："HTTP 连接不加密，密码和文件将以明文传输。建议使用 HTTPS。"

### 12.4 App Transport Security（ATS）策略

**问题**：iOS 的 ATS 默认禁止 HTTP 明文请求。当前 Info.plist 仅配置了 `NSAllowsLocalNetworking = true`，这只允许局域网 IP（如 192.168.x.x、10.x.x.x）的 HTTP 访问。如果用户尝试连接公网 HTTP 地址，请求会被 ATS 拦截。

**策略（推荐）**：不修改 Info.plist，通过代码层面处理：

| 场景 | 行为 |
|------|------|
| HTTPS 地址 | 正常请求（ATS 不拦截） |
| HTTP + 局域网 IP（10.x.x.x / 172.16~31.x.x / 192.168.x.x / localhost） | 允许（`NSAllowsLocalNetworking` 已支持） |
| HTTP + 公网地址 | 账户编辑页阻止保存，提示"公网地址必须使用 HTTPS，或改用局域网 IP 访问" |

**判断逻辑**：在 `WebDAVAccountEditView` 保存时校验：

```swift
func isLocalNetwork(host: String) -> Bool {
    if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
    if host.hasSuffix(".local") { return true }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else { return false }
    if parts[0] == 10 { return true }
    if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
    if parts[0] == 192 && parts[1] == 168 { return true }
    return false
}
```

**优势**：不引入 `NSAllowsArbitraryLoads = true`，保持 ATS 安全性，不增加 App Store 审核风险。对大多数 WebDAV 使用场景（坚果云 HTTPS、局域网 NAS/Alist HTTP）均无影响。

---

## 十三、性能考量

| 项目 | 策略 |
|------|------|
| 目录加载 | PROPFIND Depth:1 单层加载，按需请求子目录 |
| 大目录 | 一次最多展示 1000 个条目；超出时提示用户进入子目录浏览 |
| 下载模式 | 串行下载（避免服务器连接数限制） |
| 下载超时 | 单文件 5 分钟，超时自动跳过 |
| 临时文件清理 | 导入完成后立即清理 `tmp/import_temp/` |
| 文件去重 | 复用现有 SHA256 哈希去重机制 |
| 内存占用 | 使用 URLSession downloadTask 流式写入磁盘，不在内存中持有文件 |

---

## 十四、与百度网盘 Open API 方案的对比

| 维度 | WebDAV 方案 | 百度 Open API 方案 |
|------|------------|-------------------|
| 通用性 | ✅ 支持所有 WebDAV 兼容服务 | ❌ 仅百度网盘 |
| 百度网盘支持 | ⚠️ 需 Alist 桥接 | ✅ 原生 API |
| 配置门槛 | ⚠️ 用户需知道 WebDAV 地址 | ⚠️ 需配置 AppKey/SecretKey |
| 下载速度（百度） | 取决于 Alist + 账号等级 | 取决于账号等级 |
| 第三方依赖 | ✅ 无（纯 Foundation） | ✅ 无 |
| 维护成本 | ✅ 标准协议，不受 API 变更影响 | ⚠️ 百度 API 可能变更 |
| App Store 审核 | ✅ 无 OAuth，无特殊审核点 | ⚠️ OAuth 需审核 |
| 多网盘支持 | ✅ 天然支持 | ❌ 需要每个网盘单独对接 |

**建议**：两个方案可以共存——WebDAV 方案面向高级用户（有 NAS/Alist 的群体），百度 Open API 方案面向大众用户。互不冲突。

---

## 十五、开发计划

| 阶段 | 内容 | 涉及文件 | 要点 |
|------|------|---------|------|
| 阶段 0 | 共享基础设施：KeychainHelper | 1 个新增文件 | 通用 Keychain 读写封装，方案 A/C 共用 |
| 阶段 1 | Core 层：WebDAVClient + XML 解析 + SessionDelegate | 3 个新增文件 | PROPFIND/GET/OPTIONS、XML 解析（含父目录过滤、URL 解码）、Basic Auth、自签证书代理 |
| 阶段 2 | Domain 层：实体 + Service | 3 个新增文件 | WebDAVAccount、WebDAVFile（Domain 层自持 audioExtensions）、WebDAVService |
| 阶段 3 | Data 层：账户持久化 | 1 个新增文件 | 基于 KeychainHelper + UserDefaults JSON 存储 |
| 阶段 4 | Presentation 层：UI | 4 个新增文件 | 账户列表、账户编辑（含 ATS 校验）、文件浏览器、下载进度 |
| 阶段 5 | 集成与错误处理 | 4 个修改文件 | 设置页入口、@StateObject 依赖注入、错误码、主题适配 |
| 阶段 6 | 测试 | 1 个测试文件 | WebDAVXMLParser 测试（含父目录过滤、中文路径）、WebDAVClient Mock 测试 |

---

## 附录 A：常用 WebDAV 服务配置参考

| 服务 | WebDAV 地址 | 认证方式 | 备注 |
|------|------------|---------|------|
| 坚果云 | `https://dav.jianguoyun.com/dav/` | Basic（应用专用密码） | 免费 1GB/月上传，3GB/月下载 |
| Alist | `http://{IP}:5244/dav/` | Basic | 可桥接百度网盘、阿里云盘等 |
| 群晖 NAS | `https://{IP}:5006/` 或 `http://{IP}:5005/` | Basic / Digest | 需安装 WebDAV Server 套件 |
| InfiniCLOUD | `https://{user}.teracloud.jp/dav/` | Basic | 免费 20GB |
| Nextcloud | `https://{domain}/remote.php/dav/files/{user}/` | Basic | 自建云盘 |
| Box | `https://dav.box.com/dav/` | Basic | 海外服务 |

## 附录 B：PROPFIND 响应 XML 结构参考

```xml
<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Music/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>Music</d:displayname>
        <d:resourcetype><d:collection/></d:resourcetype>
        <d:getlastmodified>Thu, 19 Mar 2026 08:00:00 GMT</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Music/song.mp3</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>song.mp3</d:displayname>
        <d:getcontentlength>4398046</d:getcontentlength>
        <d:getcontenttype>audio/mpeg</d:getcontenttype>
        <d:getlastmodified>Wed, 18 Mar 2026 12:30:00 GMT</d:getlastmodified>
        <d:resourcetype/>
        <d:getetag>"abc123"</d:getetag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
```
