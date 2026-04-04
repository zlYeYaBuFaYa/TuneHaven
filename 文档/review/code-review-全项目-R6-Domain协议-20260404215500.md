# 代码 Review - 全项目：R6 Domain - Repository 协议 - 第 1 轮

> 日期：2026-04-04 | 模式：全项目 | 类型：AI 自审

## 文件清单（20 文件 / 351 行）

| 文件 | 行数 |
|------|------|
| Domain/Repositories/SongRepository.swift | 25 |
| Domain/Repositories/PlaylistRepository.swift | 18 |
| Domain/Repositories/PlaylistGroupRepository.swift | 12 |
| Domain/Repositories/SearchHistoryRepository.swift | 9 |
| Domain/Repositories/AudioEngineProtocol.swift | 37 |
| Domain/Repositories/AudioSessionManaging.swift | 6 |
| Domain/Repositories/AudioMetadataParsing.swift | 5 |
| Domain/Repositories/EmbeddedLyricsReading.swift | 5 |
| Domain/Repositories/FileImporting.swift | 6 |
| Domain/Repositories/FileStorageProviding.swift | 23 |
| Domain/Repositories/ImageCacheManaging.swift | 21 |
| Domain/Repositories/NowPlayingManaging.swift | 16 |
| Domain/Repositories/ShareServerProviding.swift | 53 |
| Domain/Repositories/WebDAVClientProtocol.swift | 16 |
| Domain/Repositories/WebDAVAccountStoring.swift | 9 |
| Domain/Repositories/LyricsAPIProviding.swift | 15 |
| Domain/Repositories/SubscriptionProviding.swift | 46 |
| Domain/Repositories/UserPreferencesProviding.swift | 15 |
| Domain/Repositories/BackgroundTaskProviding.swift | 7 |
| Domain/Repositories/CoverImageProcessing.swift | 7 |

## 结论：有条件通过（1 项技术债需后续处理）

## 延后处理

| # | 级别 | 描述 | 原因 |
|---|------|------|------|
| 1 | 🔴→技术债 | ImageCacheManaging 引入 UIKit（UIImage），违反 Domain 无 UI 依赖原则 | 需将 UIImage 替换为 Data 类型，涉及整个调用链改造 |
| 2 | 🟡 | FileStorageProviding 同时 AnyObject + Sendable，并发模型不清晰 | 需明确实现的并发策略 |
| 3 | 🟡 | 读操作 async 非 throws vs 写操作 async throws，策略不统一 | 需要团队约定统一错误处理策略 |
| 4 | 🟡 | AudioEngineProtocol.load 为 async 非 throws | 加载失败无法在类型层面表达 |
| 5 | 🟡 | AudioMetadataParsing.parse 非 throws | 解析失败走兜底值，需文档化 |
| 6 | 🟡 | PlaybackState.error 用 String(describing:) 比较 | 等价性不可靠 |
| 7 | 🟡 | ShareServerProviding 闭包未标 @Sendable | 可能与 MainActor 冲突 |
| 8 | 🟡 | UserPreferencesProviding 未标 @MainActor | 与同类协议不一致 |
| 9 | 🟡 | WebDAVClientFactory 未标 Sendable | 并发传递边界不清 |
| 10 | 🟢 | 协议命名后缀不统一（Protocol/Providing/Managing/Storing） | 风格一致性 |
| 11 | 🟢 | Domain 层依赖 Combine | 可接受，但可改用 AsyncStream |
