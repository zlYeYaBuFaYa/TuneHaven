# 代码 Review：全项目代码审查 - 第 3 轮

> 日期：2026-03-21 | 类型：AI 自审（最终一致性验证） | 范围：第 1、2 轮共 20 个修改文件 + CoreData 模型 + 实体层

## 结论：通过 ✅

第 1 轮修复 21 个问题 + 第 2 轮修复 4 个问题，所有修改均已验证正确。未发现新的阻塞或建议级问题。

---

| 维度         | 结论 | 说明                                                      |
| ------------ | ---- | --------------------------------------------------------- |
| 功能正确性   | ✅   | lyricsSource 哨兵值在所有 3 个写入路径 + 迁移中一致       |
| 线程安全     | ✅   | Logger 序列化、搜索竞态、CoreData observer 均正确          |
| 内存安全     | ✅   | SHA256 流式读取、WebDAV 缓冲写入无内存风险                 |
| 架构规范     | ✅   | 所有修复遵循 Clean Architecture 分层，无跨层依赖           |
| 代码风格     | ✅   | 无未使用变量、无 print、无死代码                           |
| 数据一致性   | ✅   | Hashable 契约、CoreData 哨兵值、迁移逻辑均验证通过        |
| 播放引擎     | ✅   | play() / handleInterruption / setSpeed 三处 AVPlayer 模式一致 |
| 安全性       | ✅   | WiFi 路径穿越已修复                                       |

---

## 验证清单

### 1. lyricsSource 哨兵值一致性 ✅

| 位置 | 代码 | 状态 |
|------|------|------|
| `SongMapper.toEntity` | `song.lyricsSource?.rawValue ?? -1` | ✅ |
| `SongMapper.toDomain` | `entity.lyricsSource >= 0 ? LyricsSource(rawValue:) : nil` | ✅ |
| `CoreDataSongRepository.updateLyrics` | `lyricsSource?.rawValue ?? -1` | ✅ |
| `MigrationManager.migrateLyricsSourceSentinel` | 旧 `0 AND lyricsPath == nil` → `-1` | ✅ |

值域验证：
- `-1` → nil（无歌词来源）✅
- `0` → `.embedded` ✅
- `1` → `.file` ✅
- `2` → `.manual` ✅
- `≥3`（无效 rawValue）→ `LyricsSource(rawValue:)` 返回 nil → 等效 nil ✅

### 2. AVPlayer 播放恢复模式一致性 ✅

| 位置 | 代码 | 状态 |
|------|------|------|
| `AudioEngine.play()` | `player.play(); if speed != 1.0 { player.rate = speed }` | ✅ |
| `AudioEngine.handleInterruption` | `player.play(); if speed != 1.0 { player.rate = speed }` | ✅ |
| `AudioEngine.setSpeed()` | `if isPlaying { player.rate = speed }` （变速，非恢复，正确） | ✅ |

### 3. Hashable 契约一致性 ✅

所有 Domain Entity 均采用 `id`-only 模式：

| 实体 | `==` | `hash(into:)` | 状态 |
|------|------|---------------|------|
| `Song` | `id` | `id` | ✅ |
| `Playlist` | `id` | `id` | ✅ |
| `PlaylistGroup` | `id` | `id` | ✅ |
| `QueueItem` | `id` | `id` | ✅ |

SwiftUI 兼容性：所有实体均通过 `@Published` 数组整体替换触发 UI 刷新，与 `id`-only 等值判断兼容。

### 4. 迁移逻辑验证 ✅

- **执行时机**：`CoreDataStack.load()` 之后、`playlistService` / `libraryService` 之前，无竞态
- **幂等性**：UserDefaults 标志 `lyrics_source_sentinel_migrated` 确保仅执行一次
- **错误恢复**：迁移失败不设标志，下次启动自动重试
- **迁移策略**：`lyricsSource == 0 AND lyricsPath == nil` → `-1`
  - 真正有内嵌歌词的歌曲也符合条件（lyricsPath 也为 nil），会被误迁移为 nil
  - 影响可接受：LyricsService fallthrough 链会在 Step 2 自动重新检测内嵌歌词

### 5. CoreData 模型注意事项 📝

`SongEntity.lyricsSource` 的 `defaultValueString` 仍为 `"0"`（xcdatamodel 定义），但：
- 所有 SongEntity 创建均经过 `SongMapper.toEntity`，显式设置 `lyricsSource`
- 默认值 `"0"` 在当前架构下永远不会生效
- 修改 xcdatamodel 可能触发模型兼容性检查，风险收益比不合理，记录备查即可

---

## 已知遗留问题（无变化，同第 2 轮）

| # | 问题 | 级别 | 状态 |
|---|------|------|------|
| 1 | WiFiTransferServer 二进制 multipart 上传静默失败 | ⚠️ 遗留 | 建议后续版本重构 |

---

## 审查总结

经过三轮 Review：
- **第 1 轮**：发现 35 个问题，修复 21 个，修改 17 个文件
- **第 2 轮**：发现 4 个遗漏/不一致，修复 4 个，修改 5 个文件
- **第 3 轮**：全量交叉验证，**未发现新问题**

代码质量已达到可提交标准。
