# 代码 Review：全项目 Code Review - 第 1 轮（已验证修正版）

> 日期：2026-04-01 | 类型：AI 自审 + 逐项验证 | 审查范围：全部 177 个源文件

## 结论：不通过

实际确认 **1 个阻塞问题**、**92 个重要问题**、**58 个轻微问题**。阻塞问题必须修复后方可通过。  
（注：原「WebDAVAccountStore.deleteAccount Keychain 凭据泄漏」经复核为误判：`encode` 失败时既不写入 UserDefaults 也不执行 Keychain 删除，持久化状态与删除前一致，已自本文移除。）

---

## 一、阻塞问题汇总（🔴 共 1 项）

| # | 文件 | 问题 | 说明 | 验证 |
|---|------|------|------|------|
| 1 | CoreDataSongRepository.swift | `softDelete` DB/文件系统不一致 | performBackground 闭包内标记 `softDeleted=true` 并提交事务，文件移动在事务提交后执行。崩溃发生在提交后、文件移动前时，DB 标记删除但文件仍在原位，UndoToken 无 movedFiles 条目导致不可撤销 | ✅ 已验证：lines 115-151，事务与文件移动分离 |

---

## 二、重要问题汇总（🟡 共 92 项）

> 以下所有具体断言均经源码逐一验证确认。

### 跨模块集成问题（6 项）

| # | 问题 | 涉及模块 | 验证 |
|---|------|---------|------|
| X-1 | ShareService 第 194、370 行直接引用 `SandboxPathManager` | Domain → Core | ✅ `SandboxPathManager.syncExtractURL` 和 `.musicFileURL(relativePath:)` |
| X-2 | 11 个 Domain Service 直接引用 `AppLogger.shared` | Domain → Core | ✅ grep 确认 11 个文件 |
| X-3 | `SemanticColor` 暗色变体已定义但从未使用 | App → Presentation | ✅ `dangerDark`/`warningDark` 等已定义，无调用点 |
| X-4 | `FileStorageProviding` 全部方法同步，从 @MainActor 调用阻塞 UI | Domain → Core | ✅ `sha256(of:)`、`copyToMusic` 等均为同步方法 |
| X-5 | `ImageCacheManaging` Domain 协议 import UIKit（代码有 TODO） | Domain → UIKit | ✅ 代码有 `// TODO: 🟢20` 标注 |
| X-6 | ShareReceiveView/ShareSendView 硬编码 `.green`/`.orange`/`.red` | Presentation | ✅ ShareReceiveView lines 184/196/199/202, ShareSendView lines 199/238 |

### 按维度分布

| 维度 | 数量 | 代表性问题 |
|------|------|-----------|
| 逻辑正确性 | 16 | fetchRecentlyPlayed 深页获取量过大、matchSong 模糊匹配过松、fetchAlbumGroups 用 max: 取封面、SongMapper int16Nil 哨兵值与 CoreData 默认值 0 冲突、createSystemPlaylists 无并发保护 |
| 线程安全 | 10 | ImportService SHA256 在 @MainActor 同步执行、WebDAVService 取消标志未检查、SearchService Task.detached 竞争、fetchGroupDetails 三次 fetch 阻塞主线程 |
| 错误处理 | 9 | SongRepository throws 不一致、clearHistory 全量加载删除（影响极小：maxHistoryCount=10）、silently swallowed errors |
| 架构合规 | 11 | SandboxPathManager 直接引用、PlaybackState.Error 用 String 比较、ShareService import UIKit、LyricsService nonisolated 文件访问、SemanticColor 暗色未适配 |
| 性能 | 17 | buildQueue 全量加载、softDelete N+1 引用计数查询、PlaylistDetailView 排序每次渲染计算、refreshAllObjects 过度调用、PlayerView 歌词搜索每 0.5s 重算、LyricsView onChange 未做行相等性检查 |
| 内存管理 | 8 | UndoToken class 非 Sendable（var timerKey 可变）、SnackbarState 闭包强引用（4 秒持续时间）、downloadResults 全量加载 |
| API 设计 | 5 | FileStorageProviding 同步方法、SearchHistoryRepository 批量删除未用 NSBatchDeleteRequest |
| 可维护性 | 10 | 魔法数字（pageSize=1000、sortOrder -2/-1）、重复代码 batchSongCounts（两个 Repository 近乎相同）、PlayerView/LyricsView 手势代码重复（相同配置/阈值/动画参数） |

### 关键问题详述

**1. fetchRecentlyPlayed 分页（CoreDataSongRepository.swift lines 324-413）**
- 深页获取量：page=5, pageSize=20 时获取 (100+20)*10=1200 条记录
- `hasMore` 基于 totalCount（独立查询），可能与实际分页结果不一致
- 功能正常但深页效率低

**2. matchSong 模糊匹配（ShareService.swift lines 450-465）**
- 精确匹配：title+artist+album+duration 一致
- 模糊匹配：仅 title+artist 一致即取 `candidates.first`，不考虑专辑/版本差异
- 可能将现场版与录音室版视为"模糊匹配"

**3. WebDAVService 下载取消（WebDAVService.swift）**
- `isCancelRequested` 在 `cancelDownload()` 中设为 true，但 `downloadAndImport` 的循环内未检查
- 已排入 task group 的下载会全部完成

**4. ImportService 主线程阻塞（ImportService.swift）**
- `@MainActor` 类中 `processFile` 同步调用 `fileService.sha256(of:)` 和 `copyToMusic`
- SHA256 以 1MB 分块读取全文件，大文件时 UI 卡顿

**5. ShareService import UIKit（ShareService.swift line 2）**
- Domain 层 Service 导入 UIKit，仅用于 `UIDevice.current.name`（line 327）
- 违反 Clean Architecture 分层，应通过协议注入设备名

**6. softDelete N+1 引用计数查询（CoreDataSongRepository.swift lines 125-138）**
- softDelete 中对每个 unique fileHash 执行一次 count 查询检查引用计数
- seenHashes 集合缓解了重复查询，但 unique hash 数量多时仍有性能影响

**7. fetchAlbumGroups 用 max: 取封面（CoreDataSongRepository.swift lines 473-476）**
- `NSExpression(forFunction: "max:")` 对 coverImagePath 做字典序比较
- 返回的"封面"是字母序最大的路径字符串，而非有意义的封面选择

**8. SongMapper int16Nil 哨兵值（SongMapper.swift line 5）**
- 使用 `Int16.min` (-32768) 作为 nil 哨兵，CoreData 默认值为 0
- `isValidTrackNumber` 中 0 通过验证（`0 >= 0`），被误判为有效 trackNumber
- year 的 isValidYear 要求 `> 0`，不受影响

---

## 三、轻微问题汇总（🟢 共 58 项）

| 类型 | 数量 | 说明 |
|------|------|------|
| 硬编码中文字符串未国际化 | 200+ | grep 确认 Presentation 层大量硬编码中文，无 NSLocalizedString 使用 |
| 魔法数字未提取常量 | ~5 | PlaybackService pageSize=1000、sortOrder -2/-1 等；部分已提取为命名常量（recentPlayedFetchMultiplier、maxHistoryCount） |
| 命名风格不一致 | ~3 | `_loadAccounts` 等少数案例 |
| 可简化的代码结构 | ~8 | AudioMetadataParser 无状态单例可改为 enum 等 |
| 辅助功能缺失 | 全局 | Presentation 层仅 SongRow.swift 有 accessibilityLabel，其余均无 |

---

## 四、修复优先级建议

### P0 - 立即修复（阻塞问题）
1. **softDelete DB/文件一致性**：将文件移动逻辑移入 performBackground 闭包内，或在移动失败时回滚 DB 状态

### P1 - 本迭代修复（重要问题）
1. ShareService 移除 UIKit 依赖，注入设备名
2. ShareService 移除 SandboxPathManager 直接引用，改用 FileStorageProviding
3. ImportService SHA256/文件复制移至后台线程
4. WebDAVService 下载循环增加 isCancelRequested 检查
5. fetchRecentlyPlayed 分页算法优化
6. matchSong 模糊匹配增加 duration 相似度阈值
7. 分享视图硬编码颜色替换为主题色
8. CoreDataPlaylistRepository 移除 refreshAllObjects 调用

### P2 - 后续迭代
1. AppLogger 单例改为协议注入
2. ImageCacheManaging UIKit 依赖抽象
3. SemanticColor 暗色变体接入使用
4. FileStorageProviding 方法改为 async
5. 搜索/过滤操作异步化
6. PlayerView/LyricsView 手势代码抽取共享 ViewModifier
7. 国际化支持
8. 全局代码风格统一

---

## 五、统计总览

| 指标 | 数值 |
|------|------|
| 审查文件数 | 177 |
| 有问题的文件数 | 68 |
| 🔴 阻塞 | 1 |
| 🟡 重要 | 92 |
| 🟢 轻微 | 58 |
| 无问题文件 | 109 |

---

## 结论

项目整体架构设计合理（Clean Architecture + MVVM 分层清晰），代码质量中等偏上。主要风险集中在：

1. **数据一致性**：softDelete 的 DB/文件系统两阶段提交缺少原子性保障
2. **架构合规性**：Domain 层个别 Service 突破分层边界（ShareService 引用 SandboxPathManager/UIKit）
3. **线程安全**：ImportService 中 SHA256/文件复制在 @MainActor 同步执行，大文件时 UI 卡顿
4. **功能完整性**：WebDAVService 下载取消机制不生效

建议优先修复阻塞问题，然后按优先级处理重要问题。修复完成后进入第 2 轮 Review。
