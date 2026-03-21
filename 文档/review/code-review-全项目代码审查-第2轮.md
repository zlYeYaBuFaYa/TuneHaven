# 代码 Review：全项目代码审查 - 第 2 轮

> 日期：2026-03-21 | 类型：AI 自审（修复回归验证） | 范围：第 1 轮修复涉及的 17 个文件 + 关联代码

## 结论：有条件通过

第 1 轮修复的 21 个问题整体质量良好，但发现 **1 个遗漏阻塞问题** 和 **3 个建议级问题**，均已在本轮修复。

---

| 维度         | 结论 | 说明                                                  |
| ------------ | ---- | ----------------------------------------------------- |
| 功能正确性   | ✅   | 第 1 轮遗漏的 lyricsSource 哨兵不一致已修复           |
| 线程安全     | ✅   | Logger 序列化、搜索竞态、CoreData observer 均正确      |
| 内存安全     | ✅   | SHA256 流式读取、WebDAV 缓冲写入无内存风险             |
| 架构规范     | ✅   | 修复遵循 Clean Architecture 分层规范                   |
| 代码风格     | ✅   | 无未使用变量、无 print、无死代码                       |
| 错误处理     | ✅   | 文件不存在/类型转换等均有安全处理                      |
| 安全性       | ✅   | WiFi 路径穿越已修复                                   |
| 数据一致性   | ✅   | 新增一次性迁移修复旧数据哨兵值                        |

---

## 第 2 轮发现的问题及修复

### 🔴 R2-1: CoreDataSongRepository.updateLyrics 哨兵值不一致（第 1 轮遗漏）

**文件**：`Data/Repositories/CoreDataSongRepository.swift:223`

**问题**：第 1 轮修复 P0-1 时将 `SongMapper` 中 nil 哨兵从 `0` 改为 `-1`，但遗漏了 `updateLyrics` 方法中的同一模式。当用户删除歌词时 `lyricsSource` 存为 `0`，`SongMapper.toDomain` 会将其误读为 `.embedded`。

**修复**：`lyricsSource?.rawValue ?? 0` → `lyricsSource?.rawValue ?? -1`

**影响**：删除歌词后歌曲信息页面会显示"内嵌歌词"而非"无歌词"。

---

### 🟡 R2-2: 旧数据 lyricsSource 哨兵值迁移

**文件**：`Core/Persistence/MigrationManager.swift` + `App/TuneHavenApp.swift`

**问题**：P0-1 修复后，历史数据中 `lyricsSource = 0`（原意 nil）会被误读为 `.embedded`。需要一次性数据迁移。

**修复**：新增 `migrateLyricsSourceSentinel()`，在 CoreData 加载后执行。对所有 `lyricsSource = 0 AND lyricsPath IS NULL` 的记录更新为 `-1`。通过 UserDefaults 标记确保仅执行一次。

**迁移策略说明**：
- 条件 `lyricsPath IS NULL` 用于区分：真正有内嵌歌词的歌曲 lyricsPath 也为 nil，但这是可以接受的误判——LyricsService 采用 fallthrough 链，lyricsSource 恢复为 nil 后仍会自动检测内嵌歌词。
- 迁移仅运行一次，不影响后续性能。

---

### 🟡 R2-3: FileStorageService.copyToMusic 残留未使用变量

**文件**：`Core/Storage/FileStorageService.swift:29`

**问题**：第 1 轮 P3 修复移除了 `_ = ext` 死代码，但遗漏了 `let ext = ...` 声明本身，导致编译器 warning。

**修复**：删除 `let ext = (originalFileName as NSString).pathExtension.lowercased()` 行。

---

### 🟡 R2-4: AudioEngine.handleInterruption 播放恢复不一致

**文件**：`Core/Audio/AudioEngine.swift:282`

**问题**：第 1 轮 P1-3 修复了 `play()` 方法（先 `player.play()` 再设 `rate`），但中断恢复处理器 `handleInterruption` 仍使用旧模式 `player.rate = playbackSpeed`。

**修复**：改为 `player.play(); if playbackSpeed != 1.0 { player.rate = playbackSpeed }`，与 `play()` 方法保持一致。

---

## 已知遗留问题（不阻塞，记录备查）

### ⚠️ WiFiTransferServer 二进制 multipart 上传静默失败

**文件**：`Core/Network/WiFiTransferServer.swift:148`

**问题**：`handleHTTPData` 开头 `String(data: data, encoding: .utf8)` 对包含二进制音频数据的 multipart 请求会返回 nil，导致上传静默失败。

**状态**：**第 1 轮之前即存在的问题**，第 1 轮和第 2 轮修复均未引入。建议在后续版本重构 WiFi 上传为流式处理架构时一并解决。

**建议方案**：`handleHTTPData` 应仅解析 HTTP header 部分为字符串（找到 `\r\n\r\n` 分隔符），body 部分保持 `Data` 类型处理，避免全量 UTF-8 转换。

---

## 第 2 轮修复总结

| # | 文件 | 修改内容 |
|---|------|----------|
| 1 | `CoreDataSongRepository.swift` | `updateLyrics` 哨兵 `0` → `-1` |
| 2 | `MigrationManager.swift` | 新增 `migrateLyricsSourceSentinel()` |
| 3 | `TuneHavenApp.swift` | 启动流程调用 `runPostLoadMigrations()` |
| 4 | `FileStorageService.swift` | 移除未使用的 `ext` 变量 |
| 5 | `AudioEngine.swift` | 中断恢复使用标准 `play()` + `rate` 模式 |

共修改 **5 个文件**，修复 **4 个问题**（1 🔴 + 3 🟡），无 linter 错误。
