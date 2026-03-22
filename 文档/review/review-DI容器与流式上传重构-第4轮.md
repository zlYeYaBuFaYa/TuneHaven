# 方案 Review：DI 容器与流式上传重构 - 第 4 轮

> 日期：2026-03-22 | 类型：AI 自审（确认修复）

## 结论：通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 4 项 Review 问题全部覆盖 |
| 可执行性 | ✅ | 第 3 轮问题已修复，伪代码可直接编码 |
| 描述清晰度 | ✅ | TuneHavenApp 内部方法（initialize、ensureOpenInHandler、onAppear、onChange）已补充完整改写示例 |
| 逻辑合理性 | ✅ | DI 容器设计、流式上传两阶段策略、mmap + 直写优化均逻辑自洽 |
| 架构合规 | ✅ | DI 容器在 App 层，Service 通过 environmentObject 注入，符合 Clean Architecture |
| 影响评估 | ✅ | 文件清单已补充测试文件；9 处 TuneHavenApp 内部属性引用已明确列出 |
| 边界处理 | ✅ | 临时文件清理（启动 + defer）、Header 限制、非上传兼容、Swift 6 Sendable |
| 性能考量 | ✅ | mmap + fileData.write(to:) 直写避免拷贝，内存峰值可控 |

## 第 3 轮问题修复确认

| 问题 | 修复方式 | 验证 |
|------|----------|------|
| 🟡 TuneHavenApp 内部方法引用未覆盖 | 补充 initialize()、ensureOpenInHandler()、onAppear、onChange 完整改写示例，列出 9 处引用 | ✅ |
| 🟡 LyricsServiceTests.swift 未在文件清单 | 文件清单已增加 | ✅ |
| 🟢 parseMultipart Data 拷贝 | 补充说明改为 `fileData.write(to:)` 直写 | ✅ |
| 🟢 StreamingUploadContext Sendable | 已添加 `@unchecked Sendable` | ✅ |

## 最终文件修改清单汇总

### 需求 1：DI 容器架构重构（8 个文件）

| # | 文件 | 改动 |
|---|------|------|
| 1 | `TuneHaven/App/AppDIContainer.swift` | **新增**：DI 容器 |
| 2 | `TuneHaven/App/TuneHavenApp.swift` | 重构：10 @StateObject → 1，内部方法 9 处引用改 container.xxx |
| 3 | `TuneHaven/Domain/Services/PlaybackService.swift` | 移除 shared，private init → internal init |
| 4 | `TuneHaven/Domain/Services/LyricsService.swift` | 移除 shared，添加 ObservableObject 遵守 |
| 5 | `TuneHaven/Presentation/Player/PlayerView.swift` | 3 处 LyricsService.shared → @EnvironmentObject |
| 6 | `TuneHaven/Presentation/Settings/SongInfoEditView.swift` | 2 处 LyricsService.shared → @EnvironmentObject |
| 7 | `TuneHaven/Presentation/Player/LyricsSearchView.swift` | 3 处 LyricsService.shared → @EnvironmentObject |
| 8 | `TuneHavenTests/LyricsServiceTests.swift` | LyricsService.shared → LyricsService() |

### 需求 2：流式上传重构（1 个文件）

| # | 文件 | 改动 |
|---|------|------|
| 9 | `TuneHaven/Core/Network/WiFiTransferServer.swift` | 流式上传、StreamingUploadContext、cleanupTempFiles、parseMultipart 直写优化 |

### 不改动

| 文件 | 原因 |
|------|------|
| `TuneHaven/Core/Audio/AudioEngine.swift` | 渐进策略，保留 shared |
| `TuneHaven/Presentation/Root/RootTabView.swift` | @EnvironmentObject 声明不变（新增的 lyricsService 由 TuneHavenApp 注入，RootTabView 本身不使用） |

## 遗留事项（非阻塞，后续迭代）

1. AudioEngine.shared 完全移除 → 下一轮 DI 重构
2. PlaybackService 内部 PlayQueueService / MusicLibraryService 注入 → Clean Architecture 全面重构
3. 上传进度的文件名获取 → 后续功能优化
