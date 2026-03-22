# 代码 Review：全局代码审查 - 第 2 轮

> 日期：2026-03-22 | 类型：AI 自审（修复验证） | 范围：第 1 轮问题修复验证

## 结论：通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ✅ | 业务逻辑完整，核心流程自洽 |
| 错误处理 | ✅ | AppError 体系完善，哨兵值已统一为 SongMapper.int16Nil 常量 |
| 安全 | ✅ | SandboxPathManager 统一路径、SecurityScoped URL 正确 |
| 线程安全 | ✅ | @MainActor 使用正确，PlaybackService 已正确注入共享的 libraryService |
| 架构合规 | ✅ | Clean Architecture 分层良好（单 Target 项目中默认参数引用 Data 层为已知架构债务，模块化时处理） |
| 代码风格 | ✅ | 命名规范，日志写入逻辑已通过 FileLogWriter 消除重复 |
| API 设计 | ✅ | 接口语义清晰，async throws 一致 |
| 性能 | ✅ | DurationFormatter 已统一，消除重复格式化逻辑 |
| 内存管理 | ✅ | [weak self] 使用正确，cancellables 正确存储 |
| 可维护性 | ✅ | AppStorageKey 常量已补全，代码一致性提升 |

---

## 第 1 轮问题修复验证

| # | 级别 | 问题 | 修复状态 | 验证结果 |
|---|------|------|---------|---------|
| 1 | 🔴 | PlaybackService 冗余 libraryService 实例 | ✅ 已修复 | TuneHavenApp.initialize() 中已添加 `playbackService.configure(libraryService: libraryService)` |
| 2 | 🔴 | Domain 层引用 Data 层具体实现 | ⚠️ 已知债务 | 单 Target 项目无实际模块依赖风险，标记为模块化时的技术债务 |
| 3 | 🟡 | lyricsSource 哨兵值分散 | ✅ 已修复 | 统一为 `SongMapper.int16Nil` 常量，所有读写位置已引用 |
| 4 | 🟡 | ErrorLogger/AppLogger 重复代码 | ✅ 已修复 | 提取 `FileLogWriter` 工具类，消除 ~50 行重复代码 |
| 5 | 🟡 | CoreDataStack merge 策略与文档不一致 | ⚠️ 文档待更新 | 保留 automaticallyMergesChangesFromParent 实现，文档将在后续步骤同步 |
| 6 | 🟡 | ThemeRegistry 冗余 NSLock | ⚠️ 低风险保留 | NSLock 开销极低，保留不影响性能，作为防御性编程保留 |
| 7 | 🟡 | 单例 vs EnvironmentObject 混用 | ⚠️ 文档待说明 | 已有合理理由（Core 层基础设施允许单例），文档将补充说明 |
| 8 | 🟡 | 时长格式化三处重复 | ✅ 已修复 | DurationFormatter 升级支持小时，TimeInterval.formattedTime 委托给 DurationFormatter |
| 9 | 🟢 | AppStorageKey 缺失常量 | ✅ 已修复 | 补充 songSortOption/songSortAscending，LibraryMainView 已更新引用 |
| 10 | 🟢 | 文档与代码不同步 | ⚠️ 待后续步骤 | 将在提交后统一更新三份根目录文档 |
| 11 | 🟢 | LyricsLine UUID 生成 | ⚠️ 可接受 | 性能影响微小，保留现有实现 |
| 12 | 🟢 | clearAll async 标注 | ⚠️ 低优先级 | 保留，调用方已适配 |

---

## 本轮新增检查

### FileLogWriter 提取验证
- ✅ `FileLogWriter` 为 `private final class`，不暴露给外部
- ✅ `dateFormatter` 和 `isoDate()` 为 `static`，ErrorLogger/AppLogger 共享
- ✅ 轮转逻辑（rotateIfNeeded）接收 url 参数，支持不同日志文件
- ✅ backupSuffix 默认 `.old`，与原有行为一致

### SongMapper.int16Nil 统一验证
- ✅ `SongMapper.toEntity` 中 lyricsSource/trackNumber/year 三处均使用 `Self.int16Nil`
- ✅ `CoreDataSongRepository.updateLyrics` 中使用 `SongMapper.int16Nil`
- ✅ `SongMapper.isValidOptionalInt16` 和 `isValidLyricsSource` 均引用 `int16Nil`
- ✅ 兼容旧数据（仍检查 `0` 和 `-1` 旧哨兵值）

### PlaybackService 注入验证
- ✅ `configure(libraryService:)` 在 CoreDataStack.load() 之后、loadSongs() 之前调用
- ✅ 调用时机正确，确保 libraryService 已初始化但尚未使用

---

## 遗留事项（非阻塞）

1. **技术债务**：Domain 层 Service 默认参数引用 Data 层具体实现 — 模块化拆分时处理
2. **文档同步**：三份根目录文档需更新（主题列表、错误类型数量、架构说明等）— 提交后执行
3. **CoreDataStack 文档**：技术设计文档中"显式 merge"描述需更新为"自动 merge"
