# TuneHaven

> 一款 iOS 本地优先音乐播放器：基础播放离线可用，Premium 解锁无损、高级主题、WebDAV 与在线歌词

[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18.0+-blue.svg)](https://apple.com/ios)
[![Xcode](https://img.shields.io/badge/Xcode-26+-brightgreen.svg)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

---

## 项目概述

TuneHaven 是一款功能完整的 iOS 本地音乐播放器，支持多种方式导入本地音乐文件，提供完整的音乐播放、歌单管理、歌词显示和主题切换功能。应用采用 SwiftUI 构建界面，遵循 Clean Architecture 分层架构，使用 Core Data 进行数据持久化。

### 核心特性

- **音乐导入**：文件应用、Apple Music、Cloud Drive、WiFi 局域网传输、二维码分享直传；WebDAV 需 Premium
- **播放控制**：播放/暂停/切歌、多种播放模式、倍速播放、定时关闭
- **音乐库浏览**：全部歌曲、按艺术家/专辑分类浏览，支持排序与搜索
- **歌单管理**：自定义歌单、系统歌单（我喜欢/最近播放）、歌单分组、批量操作
- **歌词显示**：内嵌歌词、LRC 文件解析、歌词字形转换；在线歌词搜索需 Premium
- **主题系统**：4 套内置主题（素云白简/晴空蔚蓝/暮光玫瑰/星际穹顶），每套主题固定深浅色风格。免费档可用素云白简、晴空蔚蓝
- **订阅**：StoreKit 2 年度订阅与终身买断；试用 30 天。设置里的「订阅管理」是列表第一项，默认折叠
- **后台播放**：后台播放与锁屏控制

### 设计理念

- 曲库本地优先：基础有损播放、歌单与本地导入无需订阅；Premium 才解锁无损播放、高级主题、WebDAV 与在线歌词
- 灵活音乐组织：多维度浏览、歌单管理、智能分类
- 简洁优雅界面：4 套主题随心切换，每套主题固定深浅色风格
- 保护用户隐私：曲库默认留在设备上；购买校验与在线歌词按需联网

---

## 技术栈

| 类别 | 技术选型 | 说明 |
|------|---------|------|
| 开发语言 | Swift 5.0 | 主工程 SWIFT_VERSION |
| UI 框架 | SwiftUI | 声明式 UI，iOS 18.0+ |
| 数据持久化 | Core Data | 本地数据库，双上下文架构 |
| 音频播放 | AVFoundation (AVPlayer) | 支持 9 种音频格式 |
| 响应式编程 | Combine | 状态绑定与事件流 |
| 异步编程 | Swift Concurrency | async/await |
| 网络传输 | Network Framework | WiFi 传输 HTTP 服务器；WebDAV 为 Premium 导入 |
| 测试框架 | XCTest / Swift Testing | 单元测试与 UI 测试 |
| 模块化 | 单 Target | 无外部包依赖 |

### 支持的音频格式

- MP3 / M4A / AAC / ALAC / WAV / FLAC / AIFF / CAF

---

## 项目架构

项目采用 **Clean Architecture + MVVM** 分层架构，自上而下分为五层：

```
App Layer（应用层）
    |
Presentation Layer（表现层）
    |
Domain Layer（领域层）
    |
Data Layer（数据层）
    |
Core Layer（核心基础设施层）
```

### 架构特点

- **依赖方向**：Presentation → Domain ← Data。Core 是基础设施，供各层使用。Presentation 不引用 Core Data；StoreKit 只在 App 层 `StoreKitSubscriptionProvider`
- **Service 即 ViewModel**：核心 Service 采用 `@MainActor final class: ObservableObject`，由 `AppDIContainer` 创建，再经 `.environmentObject()` 注入
- **单例只留基础设施**：`AudioEngine`、`CoreDataStack`、`ImageCacheManager`、`FileStorageService` 等仍是 `static let shared`。`PlaybackService` 不是单例，由容器持有
- **已知例外**：`ImageCacheManaging` 的方法签名使用 `UIImage`

### 导航架构

采用 AppRouter 统一管理导航状态：
- 3 个 Tab 各自维护独立的 NavigationPath
- Sheet 弹窗通过 AppRouter 统一调度
- 播放器以 fullScreenCover 独立管理

---

## 项目结构

```
TuneHaven/
├── TuneHaven/                          # 主应用 Target
│   ├── App/                            # 应用入口、路由、主题
│   ├── Core/                           # 核心基础设施层
│   │   ├── Audio/                      # 音频引擎、会话管理
│   │   ├── Cache/                      # 图片缓存、缩略图生成
│   │   ├── Network/                    # WiFi 传输服务器
│   │   ├── Persistence/                # Core Data 栈、迁移管理
│   │   ├── Storage/                    # 文件存储服务
│   │   └── Utils/                      # 工具类
│   ├── Domain/                         # 领域层
│   │   ├── Entities/                   # 领域实体定义
│   │   ├── Repositories/               # Repository 协议
│   │   └── Services/                   # 业务服务
│   ├── Data/                           # 数据层
│   │   ├── Repositories/               # Core Data 实现
│   │   ├── Mappers/                    # 实体映射器
│   │   └── MetadataParser/             # 音频元数据解析
│   └── Presentation/                   # 表现层
│       ├── Root/                       # 根布局
│       ├── Library/                    # 音乐库模块
│       ├── Player/                     # 播放器模块
│       ├── Playlist/                   # 歌单模块
│       ├── Import/                     # 导入模块
│       ├── Share/                      # 二维码分享直传模块
│       ├── Sync/                       # WiFi 同步传输模块
│       ├── Settings/                   # 设置模块
│       ├── Sheets/                     # 弹窗视图
│       └── Common/                     # 通用组件
├── TuneHavenTests/                     # 单元测试
├── TuneHavenUITests/                   # UI 测试
└── 文档/                               # 项目文档
```

---

## 核心功能

### 音乐导入

| 导入方式 | 说明 |
|---------|------|
| 文件应用导入 | 通过系统 Files App 选择音乐文件 |
| Apple Music 导入 | 扫描 MPMediaLibrary，过滤 DRM，多策略导出 |
| Cloud Drive 导入 | 从云盘服务导入音乐文件（支持百度网盘等） |
| WiFi 传输 | HTTP 服务器 + 可选密码验证 + 二维码连接 |
| 二维码分享直传 | 设备间扫码直传，自动传输歌曲、封面、歌词和歌单 |

### 播放控制

- 基础控制：播放/暂停、上一曲/下一曲、进度条拖动
- 播放模式：顺序播放、单曲循环、列表循环、随机播放
- 倍速播放：0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 2.0x
- 定时关闭：15 / 30 / 45 / 60 分钟
- 后台播放与锁屏控制

### 音乐库管理

- 分类浏览：全部歌曲、艺术家、专辑
- 排序功能：按名称、艺术家、专辑、导入时间、文件大小、时长
- 搜索功能：实时搜索，支持汉字 / 拉丁包含、拼音全拼、首字母和轻度模糊（Free，纯本地），以及搜索历史
- 收藏功能：与「我喜欢」系统歌单双向联动
- 软删除机制：删除后 30 秒内可撤销

### 歌单管理

- 系统歌单：我喜欢、最近播放
- 自定义歌单：创建、编辑、删除、重命名
- 歌单分组：逻辑分组管理
- 歌单封面：自动生成或自定义封面
- 批量添加：从音乐库批量添加歌曲
- 拖拽排序：歌单列表和歌曲列表支持拖拽

### 本地备份与恢复

- 设置 → 备份与恢复：导出单个 `.tunehaven` 包（默认包含音频，也可只导出元数据）
- 恢复三模式：合并、替换曲库、仅恢复偏好。Free，不改变订阅状态
- 用「文件」App 打开 `.tunehaven` 会进入恢复页。全屏播放器或其他页面开着时先收起，播放不中断。若这时又打开了播放器或付费墙，这次不进入恢复页，并提示稍后再打开
- 导出前清掉上一份临时包。恢复完成、取消或关闭恢复页后，删除从外部打开的副本。没能弹出的那一份留到冷启动再清。冷启动发生在下一次导出或分享之前

### 歌词功能

- 歌词来源：内嵌歌词、外置 LRC 文件、在线自动匹配、手动输入
- 歌词显示：滚动列表、卡拉 OK 逐行填充效果
- 字体大小：支持缩放手势调整
- 歌词字形：简体/原文切换

### 主题系统

| 主题名称 | 标识 | 色彩模式 | 说明 | 专属背景动画 |
|---------|------|---------|------|-------------|
| 素云白简 | cloud_white | 浅色（默认） | 现代简约，清新自然绿 | 无 |
| 晴空蔚蓝 | azure_sky | 浅色 | 清朗明亮，天空蓝 | 无 |
| 暮光玫瑰 | twilight_rose | 深色 | 温暖优雅，玫瑰粉 | 无 |
| 星际穹顶 | cosmic_tech | 深色 | 星空科技，电子青 | 有 |

- 每套主题固定为浅色或深色，不支持单独切换日间/夜间/跟随系统
- 每套主题使用一套固定色板（`ThemeColorPalette`），不再区分 Light/Dark

---

## 环境要求

| 项目 | 要求 |
|------|------|
| Xcode | 26 或更高版本（编译 `glassEffect` 需要 iOS 26 SDK） |
| iOS 部署目标 | iOS 18.0 |
| Swift 版本 | 5.0 |

### iOS 26 过渡（A）与 Liquid Glass 第一阶段（B）

最低部署目标是 **iOS 18.0**（工程里项目与各 Target 的 `IPHONEOS_DEPLOYMENT_TARGET` 均为 18.0）。根目录 `Info.plist` 的 `UIDesignRequiresCompatibility` 仍是 YES。

这是**应急/过渡**：换 iOS 27 SDK 打包前必须删除该键。本期不删。

第一阶段在 `#available(iOS 26, *)` 上分流，并在运行时读这个键：

- 键开着，或系统低于 iOS 26：自绘 Tab 用 `.ultraThinMaterial`，路由 sheet 用不透明抬升面。导航栏默认是不透明 `palette.surface`；星际穹顶这种自绘背景页的导航栏用超薄材质。
- 键关掉且系统为 iOS 26 及以上：`#available(iOS 26, *)` 分支里导航栏交给系统，自绘 Tab 使用 `glassEffect`（不改成系统 `TabView`）。`backgroundType == .solidColor` 的素云白简、晴空蔚蓝、暮光玫瑰不再给路由 sheet 另铺不透明底。播放器全屏仍用色板渐变。星际穹顶（`hasCustomBackground`）的 sheet 仍用不透明抬升面。

浅色主题的主色和次级文字、深色主题按钮上的 `onPrimary` 已按 4.5:1 调过。静态语义红随深浅色切换：浅色保持 `#C62828`，暗色恢复改前的 `#EF4444`，避免暮光玫瑰和星际穹顶上的对比度掉到约 3:1。付费墙继续用色板和 `SemanticColor.danger(for:)`。

本机用 Xcode 26 验收时：分别保留和临时关掉兼容键（不要把关掉的结果提交），在浅色、深色主题下看 Tab、导航栏、sheet 和付费墙。iOS 18 模拟器应始终是旧外观。云端环境没有 Xcode，这条清单要在本机跑。

### 隐私清单

`TuneHaven/PrivacyInfo.xcprivacy` 放在主 Target 的同步目录里，随包进入 app bundle，避免提审 ITMS-91053。应用不追踪，也不申报收集数据类型。Required Reason API 按代码实调声明：UserDefaults `CA92.1`；文件时间戳 `C617.1`（沙盒内）和 `3B52.1`（用户授权的导入文件）；磁盘空间 `E174.1`（接收分享前读 `systemFreeSize`）。未使用 Active Keyboard 与 System Boot Time。

---

## 构建与运行

### 1. 克隆项目

```bash
git clone <repository-url>
cd TuneHaven
```

### 2. 打开项目

使用 Xcode 26+ 打开 `TuneHaven.xcodeproj`

### 3. 选择目标设备

选择 iOS 模拟器或真机（需 iOS 18.0 或更高版本）

### 4. 构建运行

```bash
# Xcode 中
Command + R

# 命令行
xcodebuild -project TuneHaven.xcodeproj -scheme TuneHaven \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 测试

项目包含两个测试 Target：

- **TuneHavenTests**：单元测试，覆盖文件存储、搜索、主题、播放队列、歌词解析、云盘导入、工具类、错误处理等模块
- **TuneHavenUITests**：UI 启动测试

### 运行测试

```bash
# Xcode 中
Product -> Test (Cmd+U)

# 命令行
xcodebuild test -project TuneHaven.xcodeproj -scheme TuneHaven \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 数据库设计

项目使用 Core Data 进行数据持久化，主要实体包括：

- **SongEntity**：歌曲信息（标题、艺术家、专辑、时长、文件路径等）
- **PlaylistEntity**：歌单信息（名称、描述、系统类型、封面等）
- **PlaylistSongEntity**：歌单-歌曲关联表
- **PlaylistGroupEntity**：歌单分组
- **PlayRecordEntity**：播放记录
- **SearchHistoryEntity**：搜索历史

---

## 主题系统开发

### 主题定义

每个主题包含一套固定色板（`ThemeColorPalette`），并固定一种 `ColorScheme`。`ThemeRegistry.bootstrap()` 注册 4 套：素云白简、晴空蔚蓝、暮光玫瑰、星际穹顶。

### 开发规范

- 所有 UI 颜色必须通过 ThemeColorPalette 获取，禁止硬编码颜色值
- 新增 UI 组件必须适配主题系统
- 主题切换后立即生效

### 自定义 EnvironmentKey

```swift
struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.cloudWhite.palette
}

// View 中使用
@Environment(\.themePalette) private var palette
Text("标题").foregroundColor(palette.textPrimary)
```

---

## 错误处理

应用通过 `AppError` 枚举统一定义了 21 种错误类型，涵盖导入、播放、WiFi、权限、存储、数据库、歌单、队列等模块。

### 错误日志

错误日志通过 ErrorLogger 统一记录，写入 Documents/Logs/error.log。

---

## 性能策略

### 图片缓存

- 两级缓存：NSCache（内存）-> 磁盘 LRU -> 从 ID3 标签提取
- 内存上限：50MB
- 磁盘上限：默认 100MB、最大 300MB

### AVPlayer 优化

- `automaticallyWaitsToMinimizeStalling = false`：本地文件无需缓冲
- `allowsExternalPlayback = false`：纯音频无需 AirPlay 视频
- 时间观察器 0.5 秒间隔

### 其他优化

- 文件去重：SHA256 全文件哈希
- CoreData 索引：byArtist, byAlbum, byImportDate, byFileHash
- Tab 切换：opacity + allowsHitTesting，避免视图重建

---

## 订阅门禁

曲库与基础播放本地优先，不是「全部功能离线免费」。

- 无损播放只有 Premium 能开始。`PlaybackService.ensureCanPlay` 覆盖应用内播放、预加载、`loadAndPlay`、播放/暂停，以及锁屏和控制中心的 Play。失败时弹出可关闭的付费墙，不会直接 `engine.play()`。
- 冷启动在订阅状态确定之后才恢复上次歌曲。Free 用户上次若是无损歌曲，不会把它恢复成当前可播放歌曲，也不会一启动就挡住音乐库。
- 上一首 / 下一首遇到无损时停在那一首并提示升级，不会静默跳过。
- 订阅降为 Free 时，正在播放的无损会暂停并提示；正在播放的有损不中断。已保存的高级主题会回到素云白简。
- WebDAV 的连接和下载、在线歌词搜索都在对应 Service 里检查权限，不只看设置页按钮。
- 高级主题：设置页上锁后才调用 `setTheme`。`setTheme` 本身不校验档位。档位变为 Free 时 `applyTier` 把暮光玫瑰、星际穹顶退回素云白简。
- 试用没有单独的到期日。已校验的 `AppTransaction.originalPurchaseDate` 优先；失败或未校验时才读 UserDefaults `app_first_launch_date`。日历日差小于 30 为试用。
- 设置「订阅管理」在列表最上方，`DisclosureGroup` 默认折叠。展开后显示试用剩余、订阅到期或终身买断，以及恢复购买、管理订阅。没有「上次同步时间」。

付费墙和设置里的「管理订阅」打开 `https://apps.apple.com/account/subscriptions`。

## 隐私说明

TuneHaven 的曲库默认留在设备上：

- 音乐文件与曲库元数据存储在用户设备本地
- 不内置广告，也不附带数据追踪或分析 SDK
- WiFi 传输和二维码分享只在局域网内工作
- 购买、恢复购买和在线歌词会按需访问 Apple 或歌词服务
- 用户可随时通过删除应用来清除本地数据

### 提审前检查

隐私政策链接集中在 `AppURLs.privacyPolicy`，当前为 `https://tunehaven.app/privacy`。付费墙使用这个常量。设置的订阅管理里也写明了同一条要求。

**提交 App Store 审核之前，必须用浏览器确认 `https://tunehaven.app/privacy` 已经可以公开打开，并且页面上是隐私政策正文。** 这个仓库不托管该网页，也不能把它当成已经上线。打不开就不要提审。

---

## 许可证

MIT License

---

## 相关文档

| 文档 | 说明 |
|------|------|
| [项目文档.md](./项目文档.md) | 详细的项目说明，包括架构、数据库设计、主题系统等 |
| [技术设计文档.md](./技术设计文档.md) | 详细的技术设计，包括各模块接口设计、数据流、交互流程等 |
| [需求文档.md](./需求文档.md) | 详细的功能需求说明与验收标准 |

---

## 代码统计

| 类型 | 行数 | 占比 |
|------|------|------|
| 主项目代码 | 19,732 行 | 80.6% |
| 测试代码 | 4,758 行 | 19.4% |
| **总计** | **24,490 行** | **100%** |

**Swift 文件总数：** 195 个

---

## 贡献

欢迎提交 Issue 和 Pull Request！

---

**Made with ❤️ for iOS music lovers**
