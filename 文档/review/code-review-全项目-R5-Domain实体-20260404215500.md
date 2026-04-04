# 代码 Review - 全项目：R5 Domain - 实体 - 第 1 轮

> 日期：2026-04-04 | 模式：全项目 | 类型：AI 自审

## 文件清单（12 文件 / 712 行）

| 文件 | 行数 |
|------|------|
| Domain/Entities/Song.swift | 63 |
| Domain/Entities/Playlist.swift | 36 |
| Domain/Entities/PlaylistGroup.swift | 16 |
| Domain/Entities/QueueItem.swift | 21 |
| Domain/Entities/PagedResult.swift | 8 |
| Domain/Entities/ParsedMetadata.swift | 18 |
| Domain/Entities/LibraryTypes.swift | 224 |
| Domain/Entities/SyncTypes.swift | 145 |
| Domain/Entities/SubscriptionTypes.swift | 56 |
| Domain/Entities/WebDAVAccount.swift | 29 |
| Domain/Entities/WebDAVFile.swift | 63 |
| Domain/Entities/LRCLibTrack.swift | 33 |

## 结论：通过（架构改进项延后）

| 维度 | 结论 | 说明 |
|------|------|------|
| 架构合规 | ✅ | 无 UIKit/CoreData 导入，均为值类型（UndoToken 除外） |
| 安全 | ✅ | WebDAVAccount 不含密码字段 |
| 逻辑正确 | 🟡 | isLossless 启发式规则不够严谨 |

## 延后处理（均为架构优化，无功能阻塞）

| # | 级别 | 描述 | 原因 |
|---|------|------|------|
| 1 | 🟡 | UndoToken 为 class + @unchecked Sendable，应移出 Entities | 架构重构，改动面大 |
| 2 | 🟡 | 多数实体未声明 Sendable | 需统一策略，逐一确认成员安全性 |
| 3 | 🟡 | Song.isLossless 与 AudioFormat.isLossless 判定规则不一致 | 需统一无损判定策略 |
| 4 | 🟡 | Song.isLossless 的 m4a+bitRate>600 启发式可能误判 | 需要更可靠的元数据检测 |
| 5 | 🟡 | SongDefaults 中文文案放在 Domain，不利于 i18n | 需迁移到 Presentation 层 |
| 6 | 🟡 | LRCLibTrack 更像外部 API DTO | 可迁移到 Data 层 |
| 7 | 🟡 | WebDAVDownloadTask 含 URL 与可变状态 | 边界模糊，可迁移到 Infrastructure |
| 8 | 🟢 | LyricsSource/SystemPlaylistType 使用 Int16（持久化泄漏） | 低影响 |
| 9 | 🟢 | 多处缺少 Hashable/Equatable 一致性 | 按需补充 |
| 10 | 🟢 | QueueItem init 写死 UUID()/Date()，测试不便 | 可按需添加完整 init |
