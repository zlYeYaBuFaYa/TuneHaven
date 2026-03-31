# TuneHaven

> 一款专注于 iOS 平台的本地音乐播放器应用，以「完全本地、简洁优雅」为设计理念

[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18.5+-blue.svg)](https://apple.com/ios)
[![Xcode](https://img.shields.io/badge/Xcode-16.0+-brightgreen.svg)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

---

## 项目概述

TuneHaven 是一款功能完整的 iOS 本地音乐播放器，支持多种方式导入本地音乐文件，提供完整的音乐播放、歌单管理、歌词显示和主题切换功能。应用采用 SwiftUI 构建界面，遵循 Clean Architecture 分层架构，使用 Core Data 进行数据持久化。

### 核心特性

- **音乐导入**：文件应用、Apple Music、Cloud Drive、WiFi 局域网传输、二维码分享直传
- **播放控制**：播放/暂停/切歌、多种播放模式、倍速播放、定时关闭
- **音乐库浏览**：全部歌曲、按艺术家/专辑分类浏览，支持排序与搜索
- **歌单管理**：自定义歌单、系统歌单（我喜欢/最近播放）、歌单分组、批量操作
- **歌词显示**：支持内嵌歌词、LRC 文件解析、在线歌词搜索、歌词字形转换
- **主题系统**：6 套内置主题，支持深色/浅色模式切换
- **后台播放**：后台播放与锁屏控制

### 设计理念

- 完全本地播放：无需联网，所有功能离线可用
- 灵活音乐组织：多维度浏览、歌单管理、智能分类
- 简洁优雅界面：6 套主题随心切换，日夜间模式自适应
- 保护用户隐私：所有数据仅存储在本地，不上传任何信息

---

## 技术栈

| 类别 | 技术选型 | 说明 |
|------|---------|------|
| 开发语言 | Swift 5.0 | 主工程 SWIFT_VERSION |
| UI 框架 | SwiftUI | 声明式 UI，iOS 18.5+ |
| 数据持久化 | Core Data | 本地数据库，双上下文架构 |
| 音频播放 | AVFoundation (AVPlayer) | 支持 9 种音频格式 |
| 响应式编程 | Combine | 状态绑定与事件流 |
| 异步编程 | Swift Concurrency | async/await |
| 网络传输 | Network Framework | WiFi 传输 HTTP 服务器 |
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

- **依赖方向严格单向**：Presentation -> Domain <- Data
- **Service 即 ViewModel**：所有核心 Service 采用 `@MainActor final class: ObservableObject` 模式
- **单例组件管理**：AudioEngine、PlaybackService、CoreDataStack 等核心组件统一管理
- **依赖注入**：启动时在 TuneHavenApp 中通过 `.environmentObject()` 注入

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
- 搜索功能：实时搜索，支持搜索历史
- 收藏功能：与「我喜欢」系统歌单双向联动
- 软删除机制：删除后 30 秒内可撤销

### 歌单管理

- 系统歌单：我喜欢、最近播放
- 自定义歌单：创建、编辑、删除、重命名
- 歌单分组：逻辑分组管理
- 歌单封面：自动生成或自定义封面
- 批量添加：从音乐库批量添加歌曲
- 拖拽排序：歌单列表和歌曲列表支持拖拽

### 歌词功能

- 歌词来源：内嵌歌词、外置 LRC 文件、在线自动匹配、手动输入
- 歌词显示：滚动列表、卡拉 OK 逐行填充效果
- 字体大小：支持缩放手势调整
- 歌词字形：简体/原文切换

### 主题系统

| 主题名称 | 说明 | 专属背景动画 |
|---------|------|-------------|
| 翠野清风 | 默认主题 | 无 |
| 玫瑰梦境 | 浪漫粉色系 | 有 |
| 霜色风雅 | 冷色调雅致 | 有 |
| 赤焰科技 | 科技感红黑 | 有 |
| 漫画波普 | 波普艺术风 | 有 |
| 水墨丹青 | 中国水墨风 | 有 |

- 颜色模式：跟随系统、日间模式、夜间模式
- 每套主题提供完整的 Light/Dark 色板

---

## 环境要求

| 项目 | 要求 |
|------|------|
| Xcode | 16.0 或更高版本 |
| iOS 部署目标 | iOS 18.5 |
| Swift 版本 | 5.0 |

---

## 构建与运行

### 1. 克隆项目

```bash
git clone <repository-url>
cd TuneHaven
```

### 2. 打开项目

使用 Xcode 16.0+ 打开 `TuneHaven.xcodeproj`

### 3. 选择目标设备

选择 iOS 模拟器或真机（需 iOS 18.5 或更高版本）

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

每个主题包含 Light/Dark 两套完整色板，定义 22 个颜色属性。

### 开发规范

- 所有 UI 颜色必须通过 ThemeColorPalette 获取，禁止硬编码颜色值
- 新增 UI 组件必须适配主题系统
- 主题切换和颜色模式变更立即生效

### 自定义 EnvironmentKey

```swift
struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.meadowBreeze.lightPalette
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

## 隐私说明

TuneHaven 高度重视用户隐私：

- 所有用户数据仅存储在用户设备本地
- 应用不会上传、收集或分享任何用户数据
- 不包含任何数据追踪或分析 SDK
- WiFi 传输和二维码分享直传功能仅在局域网内工作
- 用户可随时通过删除应用来彻底清除所有数据

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
