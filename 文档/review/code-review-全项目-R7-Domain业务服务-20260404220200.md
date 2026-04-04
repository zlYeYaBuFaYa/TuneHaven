# 代码 Review - 全项目：R7 Domain - 业务服务 - 第 1 轮

> 日期：2026-04-04 | 模式：全项目 | 类型：AI 自审

## 文件清单（14 文件 / 2667 行）

| 文件 | 行数 |
|------|------|
| Domain/Services/ShareService.swift | 610 |
| Domain/Services/PlaybackService.swift | 459 |
| Domain/Services/LyricsService.swift | 330 |
| Domain/Services/WebDAVService.swift | 262 |
| Domain/Services/ImportService.swift | 214 |
| Domain/Services/PlayQueueService.swift | 154 |
| Domain/Services/MusicLibraryService.swift | 142 |
| Domain/Services/SubscriptionService.swift | 130 |
| Domain/Services/PlaylistService.swift | 106 |
| Domain/Services/SearchService.swift | 81 |
| Domain/Services/SleepTimerService.swift | 69 |
| Domain/Services/PlaylistGroupService.swift | 56 |
| Domain/Services/LibraryGrouping.swift | 31 |
| Domain/Services/CloudDriveProvider.swift | 23 |

## 结论：通过（关键问题已修复，架构优化延后）

## 已修复问题

| # | 级别 | 文件 | 描述 | 修复方式 |
|---|------|------|------|---------|
| 1 | 🟡 | LyricsService:257,297 | songTitle 拼入路径存在路径穿越风险 | 过滤 / 和 .. 字符 |
| 2 | 🟡 | ImportService:202 | DB 插入失败后已复制文件未清理 | catch 分支添加 removeItem 清理 |
| 3 | 🟡 | PlaybackService:188 | seek() 无边界检查，可能传入负值或超出 duration | 添加 clamp 到 [0, duration] |
| 4 | 🟡 | PlaylistService:40 | updatePlaylist 缺少名称校验（空名/保留名） | 复用 createPlaylist 校验逻辑 |

## 延后处理

| # | 级别 | 描述 | 原因 |
|---|------|------|------|
| 1 | 🟡 | PlaybackService:69 恢复 Task 未存储/取消，可能覆盖用户队列 | 需要引入 Task 管理，改动面较大 |
| 2 | 🟡 | PlaybackService:172 playPrevious 无损跳过与 playNext 不一致 | 需要在 PlayQueueService 添加方法 |
| 3 | 🟡 | PlaybackService:396 SleepTimer 每秒触发 objectWillChange | 需要改变 View 的观察方式 |
| 4 | 🟡 | ShareService:474 进度计数器并发不准 | 概率低，可接受 |
| 5 | 🟡 | ShareService:310 cancelReceive 未中断进行中循环 | 需引入取消标记 |
| 6 | 🟡 | ShareService:143 N+1 串行网络请求 | 改用 TaskGroup，需评估并发限制 |
| 7 | 🟡 | ShareService:328 sessionToken 始终为空 | 安全增强，局域网场景风险可控 |
| 8 | 🟡 | MusicLibraryService:76 toggleFavorite 本地更新可能不一致 | 需从 Repo 重新 fetch |
| 9 | 🟡 | SubscriptionService:119 transactionTask 无 deinit 取消 | 需添加 deinit |
| 10 | 🟡 | LyricsService:69 exactMatch 错误被静默吞掉 | 降级搜索可恢复，影响有限 |
