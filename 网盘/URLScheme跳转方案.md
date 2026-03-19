# 方案 B：URL Scheme 跳转到百度网盘 App

> 版本：v1.2（修正版）  
> 日期：2026-03-19  
> 状态：待开发

---

## 一、需求概述

利用 iOS 系统级的「打开方式 / Open In」文件流转机制，实现从百度网盘导入音乐：

1. 用户在 TuneHaven 中点击"从百度网盘导入"
2. 跳转到百度网盘 App
3. 用户在百度网盘中找到音乐文件，点击"打开方式" → 选择 TuneHaven
4. 文件自动传回 TuneHaven 并触发导入流程

### 1.1 核心原理

```
TuneHaven                          百度网盘 App                     iOS 系统
    │                                    │                              │
    │ ① UIApplication.open(              │                              │
    │    baidunetdisk://)                 │                              │
    │ ──────────────────────────────────> │                              │
    │                                    │                              │
    │              用户在百度网盘中       │                              │
    │              下载并选择文件         │                              │
    │              → "打开方式"           │                              │
    │                                    │ ② UIDocumentInteraction      │
    │                                    │    Controller / Share Sheet   │
    │                                    │ ────────────────────────────> │
    │                                    │                              │
    │                                    │    iOS 检查 TuneHaven 注册的 │
    │                                    │    CFBundleDocumentTypes      │
    │                                    │    → 展示 TuneHaven 图标     │
    │                                    │                              │
    │ ③ 文件复制到                       │                              │
    │    Documents/Inbox/                │ <──────────────────────────── │
    │    + .onOpenURL 回调               │                              │
    │                                    │                              │
    │ ④ 触发导入流程                     │                              │
    │    ImportService.processFile()     │                              │
```

**这个机制不仅适用于百度网盘，任何能分享文件的 App（微信、QQ、钉钉、其他网盘）都能通过同样方式向 TuneHaven 发送音乐文件。**

---

## 二、iOS 文件流转机制说明

### 2.1 CFBundleDocumentTypes

通过在 Info.plist 中注册 `CFBundleDocumentTypes`，声明 TuneHaven 能处理的文件类型。注册后：

- TuneHaven 会出现在系统"打开方式"列表中
- 其他 App 通过 `UIDocumentInteractionController` 或 `UIActivityViewController` 分享文件时，TuneHaven 可作为目标
- iOS 会将文件**复制**到 TuneHaven 沙盒的 `Documents/Inbox/` 目录

### 2.2 文件接收路径

| 机制 | 文件存放位置 | 回调方式 |
|------|-------------|---------|
| "打开方式" (Open In) | `Documents/Inbox/{filename}` | SwiftUI `.onOpenURL` |
| AirDrop | `Documents/Inbox/{filename}` | 同上 |
| 拖放 (Drag & Drop) | `Documents/Inbox/{filename}` | 同上 |

### 2.3 Inbox 目录特性

- iOS 系统自动创建，App 有读写权限
- 文件由系统复制过来，属于 TuneHaven 沙盒内的副本
- **需要 App 自行清理**，否则文件会持续占用存储

---

## 三、方案优缺点分析

### 3.1 优点

| 优点 | 说明 |
|------|------|
| **实现极简** | 无需网络请求、无需 OAuth、无需 XML 解析，核心改动约 3-4 个文件 |
| **零第三方依赖** | 纯系统能力 |
| **通用性** | 不仅限于百度网盘，微信/QQ/钉钉/AirDrop 等任何 App 都能发文件过来 |
| **无审核风险** | 没有 OAuth、没有特殊 API，App Store 审核无阻力 |
| **无下载限速** | 文件由源 App 下载完成后再传过来，不受第三方 API 限速影响 |
| **用户隐私** | TuneHaven 不接触百度账号凭据 |

### 3.2 缺点

| 缺点 | 说明 | 缓解措施 |
|------|------|---------|
| **需跨 App 操作** | 用户需手动在百度网盘中找文件、点分享 | 提供清晰的引导步骤 |
| **百度网盘需先下载** | 云端文件需先下载到手机本地，才能使用"打开方式" | 引导步骤中明确说明 |
| **单次只能分享有限文件** | 百度网盘的"打开方式"通常一次分享一个文件 | 引导用户多次操作 |
| **无法在 App 内浏览网盘目录** | 必须跳到外部 App | 这是方案定位决定的，非 Bug |
| **用户需先安装百度网盘** | 设备未安装则无法使用 | 检测安装状态，未安装时提示去 App Store |

> **已验证**：百度网盘 App 支持通过"打开方式"将音频文件分享给第三方 App。

---

## 四、架构设计

### 4.1 改动极少

本方案改动量小，不需要新增独立的 Service 层或 Data 层组件。

### 4.2 文件清单

#### 新增文件（2 个）

| 文件路径 | 层级 | 职责 |
|---------|------|------|
| `Presentation/Import/OpenInImportHandler.swift` | Presentation | 处理从外部 App 接收的文件，串行导入队列，协调导入流程 |
| `Core/Utils/ExternalAppLauncher.swift` | Core | URL Scheme 跳转辅助（检测安装、打开外部 App） |

#### 修改文件（4 个）

| 文件路径 | 改动说明 |
|---------|---------|
| `Info.plist` | 新增 `CFBundleDocumentTypes`，注册 TuneHaven 可处理的音频文件类型 |
| `App/TuneHavenApp.swift` | 在 `ZStack` 上添加 `.onOpenURL` 处理外部传入文件（位于 `.task` 之后） |
| `Presentation/Import/CloudDriveImportView.swift` | 百度网盘点击行为改为 URL Scheme 跳转 + 引导说明；其他云盘保留现有 `.fileImporter` 逻辑 |
| `Presentation/Settings/SettingsImportSection.swift` | 可选：调整导入入口文案 |

---

## 五、核心流程设计

### 5.1 跳转到百度网盘

```
用户在 TuneHaven 点击"从百度网盘导入"
  │
  ├── 检测百度网盘是否安装
  │     UIApplication.shared.canOpenURL(URL(string: "baidunetdisk://")!)
  │
  ├── 已安装:
  │     1. 显示操作引导弹窗（告知用户如何操作）
  │     2. 用户点击"打开百度网盘"
  │     3. UIApplication.shared.open(URL(string: "baidunetdisk://")!)
  │     4. 跳转到百度网盘 App
  │
  └── 未安装:
        显示提示："请先安装百度网盘 App"
        可选：提供 App Store 链接
```

### 5.2 用户在百度网盘中的操作

```
（在百度网盘 App 内）
  1. 找到目标音乐文件
  2. 如果文件未下载到本地，需先点击下载（云端文件必须先下载）
  3. 下载完成后，长按文件 / 点击"更多" → "打开方式" / "发送到其他应用"
  4. 在弹出的应用列表中选择 TuneHaven
  5. iOS 系统将文件复制到 TuneHaven 沙盒，并唤起 TuneHaven
```

### 5.3 TuneHaven 接收文件

```
iOS 唤起 TuneHaven，传入文件 URL
  │
  ├── .onOpenURL { url in ... }
  │     url 指向 Documents/Inbox/{filename}
  │
  ├── OpenInImportHandler 处理（串行队列，逐个处理）:
  │     1. 入队：将 URL 加入待处理队列
  │     2. 如果当前无正在处理的任务，开始处理队首 URL:
  │        a. 校验文件扩展名（是否为支持的音频格式）
  │           → 不支持: Snackbar "不支持的文件格式"
  │        b. 校验文件大小（<= 500MB）
  │           → 超限: Snackbar "文件过大"
  │        c. 调用 ImportService.processFile(url:)
  │           → 标准导入流程（SHA256 去重、元数据解析、复制到 Music 目录）
  │        d. 清理 Inbox 中的源文件
  │        e. 刷新音乐库 libraryService.loadSongs()
  │        f. 展示导入结果 Snackbar
  │           → 成功: "已导入《歌曲名》"
  │           → 重复: "该歌曲已存在，已跳过"
  │           → 失败: 显示错误原因
  │     3. 处理完毕后，取队列下一个继续，直到队列为空
  │
  └── 特殊情况: App 未完成初始化时收到文件
        → 将 URL 加入暂存数组，等 isReady=true 后逐个处理
```

### 5.4 Inbox 清理策略

```
每次处理完接收的文件后:
  1. 立即删除已处理的 Inbox 文件（无论导入成功或失败）

启动时清理:
  cleanupOnLaunch() 中增加:
  2. 扫描 Documents/Inbox/ 目录
  3. 删除所有残留文件（上次异常退出可能留下）
```

---

## 六、核心组件设计

### 6.1 OpenInImportHandler

```swift
@MainActor
final class OpenInImportHandler {
    private let importService: ImportService
    private let libraryService: MusicLibraryService
    private let snackbar: SnackbarState
    private let log = AppLogger.shared

    private var queue: [URL] = []
    private var isProcessing = false

    init(importService: ImportService,
         libraryService: MusicLibraryService,
         snackbar: SnackbarState) {
        self.importService = importService
        self.libraryService = libraryService
        self.snackbar = snackbar
    }

    /// 将文件 URL 加入处理队列（串行处理，避免并发冲突）
    func enqueue(url: URL) {
        queue.append(url)
        processNextIfIdle()
    }

    /// 批量入队（启动时处理暂存的 URL）
    func enqueue(urls: [URL]) {
        queue.append(contentsOf: urls)
        processNextIfIdle()
    }

    private func processNextIfIdle() {
        guard !isProcessing, !queue.isEmpty else { return }
        isProcessing = true
        let url = queue.removeFirst()
        Task {
            await handleIncomingFile(url: url)
            isProcessing = false
            processNextIfIdle()
        }
    }

    private func handleIncomingFile(url: URL) async {
        let fileName = url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()

        // 1. 校验格式
        guard FileStorageService.supportedExtensions.contains(ext) else {
            snackbar.show("不支持的文件格式：.\(ext)", type: .error)
            cleanup(url: url)
            return
        }

        // 2. 校验大小
        let fileSize = FileStorageService.shared.fileSize(at: url)
        guard fileSize <= FileStorageService.maxFileSizeBytes else {
            snackbar.show("文件超过 500MB 大小限制", type: .error)
            cleanup(url: url)
            return
        }

        // 3. 调用 ImportService（复用现有 WiFi 导入方法）
        let result = await importService.processWiFiFile(
            tempURL: url, originalFilename: fileName
        )

        // 4. 清理 Inbox
        cleanup(url: url)

        // 5. 刷新音乐库
        await libraryService.loadSongs()

        // 6. 展示结果
        switch result.status {
        case .success, .successIncompleteMetadata:
            let title = result.song?.title ?? fileName
            snackbar.show("已导入「\(title)」", type: .success)
        case .skippedDuplicate:
            snackbar.show("「\(fileName)」已存在，已跳过", type: .info)
        case .skippedUnsupportedFormat:
            snackbar.show("不支持的文件格式", type: .error)
        case .skippedOversize:
            snackbar.show("文件超过大小限制", type: .error)
        case .failed:
            snackbar.show("导入失败：\(result.errorMessage ?? "未知错误")", type: .error)
        }
    }

    private func cleanup(url: URL) {
        let inboxPath = SandboxPathManager.documentsURL
            .appendingPathComponent("Inbox").path
        guard url.path.hasPrefix(inboxPath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 启动时清理 Inbox 残留文件
    static func cleanupInbox() {
        let inbox = SandboxPathManager.documentsURL
            .appendingPathComponent("Inbox", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
```

### 6.2 URL Scheme 跳转辅助

放在 `Core/Utils/ExternalAppLauncher.swift` 中：

```swift
import UIKit

enum ExternalAppLauncher {
    /// 跳转到百度网盘 App
    @discardableResult
    static func openBaiduNetdisk() -> Bool {
        guard let url = URL(string: "baidunetdisk://"),
              UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }

    /// 检测百度网盘是否已安装
    static var isBaiduNetdiskInstalled: Bool {
        guard let url = URL(string: "baidunetdisk://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
```

---

## 七、Info.plist 变更

新增 `CFBundleDocumentTypes`，声明 TuneHaven 支持的音频文件类型：

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Audio File</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.mp3</string>
            <string>public.mpeg-4-audio</string>
            <string>com.apple.m4a-audio</string>
            <string>public.aac-audio</string>
            <string>public.aiff-audio</string>
            <string>org.xiph.flac</string>
            <string>com.microsoft.waveform-audio</string>
            <string>public.aifc-audio</string>
            <string>com.apple.coreaudio-format</string>
        </array>
    </dict>
</array>
```

**字段说明：**

| 字段 | 值 | 说明 |
|------|------|------|
| `CFBundleTypeRole` | `Viewer` | 表示 App 可以查看/播放该类型文件（不声明为 Editor 以免被系统优先推荐为默认打开方式） |
| `LSHandlerRank` | `Alternate` | 表示 App 不是该类型的主处理程序，仅作为备选（避免 TuneHaven 变成系统默认音频打开方式） |
| `LSItemContentTypes` | UTType 数组 | 仅注册项目实际支持的音频格式，不使用 `public.audio` 父类型以避免对不支持的格式（如 .ogg/.opus）也出现在打开方式列表中 |

**UTType 与格式映射：**

| UTType | 对应格式 | 对应扩展名 |
|--------|---------|-----------|
| `public.mp3` | MP3 | .mp3 |
| `public.mpeg-4-audio` | MPEG-4 Audio | .m4a |
| `com.apple.m4a-audio` | Apple M4A | .m4a |
| `public.aac-audio` | AAC | .aac |
| `public.aiff-audio` | AIFF | .aiff / .aif |
| `org.xiph.flac` | FLAC | .flac |
| `com.microsoft.waveform-audio` | WAV | .wav |
| `public.aifc-audio` | AIFF-C | .aifc |
| `com.apple.coreaudio-format` | Core Audio | .caf |

> **设计决策**：不注册 `public.audio`（音频通用父类型），仅注册具体格式。这样 TuneHaven 只在源文件是支持的格式时才出现在"打开方式"列表中，避免用户选了 TuneHaven 后收到"格式不支持"的提示。

---

## 八、TuneHavenApp.swift 变更

```swift
// 新增属性
@State private var pendingImportURLs: [URL] = []
@State private var openInHandler: OpenInImportHandler?  // @State 持有引用类型：语义上为值类型设计，但在 App struct 中持有可变引用是 SwiftUI 标准实践
```

在 `body` 中的 `ZStack` 上添加（位于 `.task { await initialize() }` 之后）：

```swift
.onOpenURL { url in
    handleIncomingURL(url)
}
```

新增方法：

```swift
private func handleIncomingURL(_ url: URL) {
    AppLogger.shared.info("[App] onOpenURL: \(url.lastPathComponent)")

    guard isReady else {
        pendingImportURLs.append(url)
        return
    }

    ensureHandler().enqueue(url: url)
}

private func ensureHandler() -> OpenInImportHandler {
    if let handler = openInHandler { return handler }
    let handler = OpenInImportHandler(
        importService: importService,
        libraryService: libraryService,
        snackbar: snackbar
    )
    openInHandler = handler
    return handler
}
```

在 `initialize()` 末尾添加：

```swift
// 清理 Inbox 残留
OpenInImportHandler.cleanupInbox()

// 处理启动前暂存的文件
if !pendingImportURLs.isEmpty {
    let urls = pendingImportURLs
    pendingImportURLs.removeAll()
    ensureHandler().enqueue(urls: urls)
}
```

---

## 九、CloudDriveImportView 变更

**改动范围**：仅修改百度网盘 Provider 的点击行为。其他 Provider（如果后续新增）仍走现有的 `.fileImporter` 路径。

判断逻辑：

```swift
// providerRow 点击事件
Button {
    if provider.id == "baidu_netdisk" {
        // 百度网盘 → URL Scheme 跳转
        showBaiduGuide = true
    } else {
        // 其他云盘 → 系统文件选择器
        selectedProvider = provider
        showDocumentPicker = true
    }
}
```

百度网盘引导弹窗（`.alert` 或 `.confirmationDialog`）：

```
┌─────────────────────────────────────┐
│       即将跳转到百度网盘             │
│                                     │
│  在百度网盘中：                      │
│  1. 找到并下载要导入的音乐文件      │
│  2. 长按文件 → 打开方式             │
│  3. 选择 TuneHaven                  │
│  文件将自动导入到音乐库              │
│                                     │
│  [取消]           [打开百度网盘]     │
└─────────────────────────────────────┘
```

页面引导区更新：

```
┌────────────────────────────────────┐
│ ← 云盘导入                         │
├────────────────────────────────────┤
│  选择云盘                          │
├────────────────────────────────────┤
│  ☁️ 百度网盘                       │
│     在百度网盘中选择文件分享到本App  │
│     ✅ 已安装                   >  │
├────────────────────────────────────┤
│                                    │
│  操作步骤                          │
├────────────────────────────────────┤
│  1. 点击上方"百度网盘"跳转到 App   │
│  2. 找到音乐文件，先下载到手机本地  │
│  3. 下载完成后长按 → 打开方式      │
│  4. 选择 TuneHaven                 │
│  5. 文件将自动导入                 │
├────────────────────────────────────┤
│  ⚠️ 百度网盘中的云端文件需先      │
│  下载到手机本地，才能通过           │
│  "打开方式"分享                    │
├────────────────────────────────────┤
│  💡 也支持从微信、QQ、AirDrop     │
│  等 App 直接分享音频文件到本App     │
└────────────────────────────────────┘
```

---

## 十、导入结果展示

由于"打开方式"通常一次传入一个文件，使用 Snackbar 提示即可（不需要专门的结果页）：

| 结果 | Snackbar 提示 |
|------|--------------|
| 成功 | ✅ 已导入「{歌曲名}」 |
| 元数据不完整 | ✅ 已导入「{歌曲名}」（部分信息缺失） |
| 重复跳过 | ⏭️ 「{文件名}」已存在，已跳过 |
| 格式不支持 | ❌ 不支持的文件格式：.{ext} |
| 文件过大 | ❌ 文件超过 500MB 大小限制 |
| 导入失败 | ❌ 导入失败：{原因} |

---

## 十一、额外收益：通用"打开方式"支持

注册 `CFBundleDocumentTypes` 后，TuneHaven 将自动支持从**任何 App** 接收音频文件：

| 来源 App | 操作方式 | 说明 |
|----------|---------|------|
| 百度网盘 | 下载 → 打开方式 → TuneHaven | 本方案主要目标 |
| 微信 | 聊天中的音频文件 → 打开方式 → TuneHaven | 附带收益 |
| QQ | 同上 | 附带收益 |
| 钉钉 | 同上 | 附带收益 |
| 邮件 | 附件 → 打开方式 → TuneHaven | 附带收益 |
| AirDrop | Mac/iPhone 发送音频文件 → 自动打开 TuneHaven | 附带收益 |
| Safari | 下载的音频文件 → 打开方式 → TuneHaven | 附带收益 |
| 文件 App | 任意位置的文件 → 分享 → TuneHaven | 附带收益 |
| 其他网盘 App | 阿里云盘、夸克等 → 打开方式 → TuneHaven | 附带收益 |

> **CFBundleDocumentTypes 注册**本身就是一个高价值的独立功能，即使不做百度网盘跳转，也值得实现。

---

## 十二、边界情况处理

| 场景 | 处理方式 |
|------|---------|
| App 在后台被系统杀死后收到文件 | iOS 会重新启动 App 并传入 URL，`pendingImportURLs` 数组确保初始化完成后逐个处理 |
| 连续快速接收多个文件 | OpenInImportHandler 内置串行队列，逐个处理避免 ImportService 并发冲突 |
| 接收的文件不在 Inbox | `.onOpenURL` 回调的 URL 可能不在 Inbox（如 AirDrop），需兼容处理——校验文件是否存在后正常导入，仅对 Inbox 内的文件执行清理 |
| 接收非音频文件 | 校验扩展名，不支持的格式给 Snackbar 提示。因不注册 `public.audio` 父类型，绝大多数情况下不会收到不支持的格式 |
| Inbox 空间未释放 | 每次处理后立即清理 + 启动时兜底清理 |
| 百度网盘未安装 | 检测后提示"请先安装百度网盘 App"，可引导去 App Store |
| App 尚未初始化完成时收到多个文件 | 全部暂存到 `pendingImportURLs` 数组，初始化完成后批量入队 |

---

## 十三、与其他方案对比

| 维度 | 方案 B（本方案） | 方案 A（百度 Open API） | 方案 C（WebDAV） |
|------|-----------------|----------------------|----------------|
| 实现复杂度 | ⭐（最简单） | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| 新增文件数 | 2 个 | 8 个 | 11 个 |
| 修改文件数 | 4 个 | 5 个 | 4 个 |
| 用户体验 | 需跨 App 操作 | App 内完成 | App 内完成 |
| 配置门槛 | 无（装了百度网盘就行） | 需配置 AppKey/SecretKey | 需知道 WebDAV 地址 |
| 通用性 | ✅ 任何 App 都能发文件 | ❌ 仅百度网盘 | ✅ 所有 WebDAV 服务 |
| 批量操作 | ⚠️ 通常一次一个文件 | ✅ 支持多选 | ✅ 支持多选 |
| 下载限速影响 | 无（百度网盘自己下载） | 受账号等级影响 | 取决于服务端 |
| 审核风险 | 无 | OAuth 需审核 | 无 |
| 依赖 | 无 | 百度 API | 无 |

---

## 十四、开发计划

| 阶段 | 内容 | 涉及文件 | 预计工作量 |
|------|------|---------|-----------|
| 阶段 1 | Info.plist 注册音频文件类型 | Info.plist | 极小 |
| 阶段 2 | 新增 ExternalAppLauncher | Core/Utils/ExternalAppLauncher.swift | 极小 |
| 阶段 3 | 实现 OpenInImportHandler（含串行队列） | Presentation/Import/OpenInImportHandler.swift | 小 |
| 阶段 4 | TuneHavenApp 添加 .onOpenURL + 暂存数组 | App/TuneHavenApp.swift | 小 |
| 阶段 5 | 更新 CloudDriveImportView（跳转逻辑 + 引导 UI） | Presentation/Import/CloudDriveImportView.swift | 小 |
| 阶段 6 | Inbox 清理逻辑 | MusicLibraryService.swift（cleanupOnLaunch） | 极小 |
| 阶段 7 | 测试（百度网盘、微信、AirDrop 验证） | - | 中 |

**总工作量评估：所有方案中最小，核心代码约 150-200 行。**

---

## 十五、建议

### 15.1 推荐策略：方案 B 先行

由于方案 B 的改动量极小且通用性强（不仅服务百度网盘，还能接收微信/QQ/AirDrop 等来源的文件），建议：

1. **先实现方案 B**：注册 CFBundleDocumentTypes + onOpenURL 处理，这是一个独立的高价值功能
2. **按需追加方案 A 或 C**：如果用户反馈需要"App 内浏览网盘"的体验，再开发 Open API 或 WebDAV 方案

### 15.2 方案 B 的局限

- 不适合需要**频繁批量导入**的用户（每次跨 App 操作比较繁琐）
- 无法在 App 内**预览**网盘目录结构
- 用户需要理解"打开方式"这个 iOS 概念（部分用户可能不熟悉）
- 百度网盘中的云端文件需**先下载到手机本地**才能分享

这些局限在方案 A / C 中不存在，因此三个方案可以**共存互补**。
