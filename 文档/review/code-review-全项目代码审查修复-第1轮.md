# 代码 Review：全项目代码审查修复 - 第 1 轮

> 日期：2026-03-21 | 类型：AI 自审 | 范围：83 个修改文件 + 9 个新文件

## 结论：不通过（已修复后进入第 2 轮）

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ❌→✅ | SongMapper 哨兵值未向后兼容、incompleteMetadataCount 恒为 0、sequential 模式未传递 dislikes |
| 错误处理 | ❌→✅ | AudioEngine 三种不同失败统一用 playbackUnsupportedFormat，语义错误 |
| 安全 | ✅ | 无新增安全问题 |
| 线程安全 | ❌→✅ | PlaybackService.sleepTimerRemaining 嵌套 ObservableObject 不触发 UI 更新；ImageCacheManager clearAll 未重置 trackedCacheSize |
| 架构合规 | ✅ | 依赖方向正确，ViewModel 提取合理 |
| 代码风格 | ❌→✅ | cleanupPendingDeletes 缩进严重错乱 |
| API 设计 | ✅ | 接口清晰，协议一致 |
| 性能 | ✅ | DurationFormatter 增加 NaN/Infinity 防护 |
| 内存管理 | ✅ | coverImage UIImage→Data 减少内存峰值 |
| 可维护性 | ✅ | 共享组件提取、ViewModel 分离 |

---

## 发现问题（9 项，全部已修复）

### 🔴 阻塞（6 项）

1. **SongMapper 哨兵值未向后兼容** — trackNumber/year 从 `0` 改为 `Int16.min`，旧数据库记录会被错误读取
   - 修复：`isValidOptionalInt16()` 同时排除 `0` 和 `Int16.min`；`isValidLyricsSource()` 同时排除 `-1` 和 `Int16.min`

2. **PlaybackService.sleepTimerRemaining 不再可观察** — 嵌套 `ObservableObject` 不会自动传播 `objectWillChange`
   - 修复：在 `setupBindings()` 中转发 `sleepTimer.$remaining` → `objectWillChange.send()`

3. **PlayQueueService sequential 模式未传递 dislikes** — `.sequential` 分支未传 dislikes 参数，与 `.repeatAll`/`.shuffle` 不一致
   - 修复：`.sequential` 分支传入 `dislikes` 参数

4. **AppleMusicImportViewModel incompleteMetadataCount 恒为 0** — `.successIncompleteMetadata` 状态未单独计数
   - 修复：增加 `incompleteMetadataCount` 变量并正确累加

5. **CoreDataSongRepository.cleanupPendingDeletes 缩进错乱** — 闭包体与 `do/catch` 块缩进不匹配
   - 修复：统一缩进层级

6. **AudioEngine 错误类型不匹配** — 音频会话失败、资源不可播放、加载异常三种场景统一用 `playbackUnsupportedFormat`
   - 修复：新增 `playbackSessionFailed`(PLY004)、`playbackLoadFailed`(PLY005) 错误类型

### 🟡 建议（3 项）

7. **DurationFormatter NaN/Infinity** — `Int(seconds)` 对 NaN 会崩溃
   - 修复：增加 `guard seconds.isFinite` 前置检查

8. **ImageCacheManager clearAll 未重置 trackedCacheSize** — 清除所有缓存文件后，追踪值仍保留旧数据
   - 修复：清理完成后在 `fileQueue` 上重置为 0

9. **CoreDataSongRepository year 检查与 mapper 不一致** — `fetchAlbumGroups` 仍用 `!= 0` 判断
   - 修复：改为 `!= 0 && != Int16.min`，与 mapper 哨兵策略一致
