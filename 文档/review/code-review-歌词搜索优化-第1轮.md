# 代码 Review：歌词搜索优化 - 第 1 轮

> 日期：2026-03-20 | 类型：AI 自审

## 结论：通过

### A. 正确性与安全

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ✅ | 降级链 4 级逐级尝试，任一命中即返回；searchMatch 优先选择 syncedLyrics；网络错误不 cooldown |
| 错误处理 | ✅ | exactMatch 的 try? 捕获网络异常继续降级；Level 2-4 的网络异常在 catch 中捕获并停止降级 |
| 安全 | ✅ | CFStringTransform 为系统 API，无安全风险 |
| 线程安全 | ✅ | LyricsService 方法为 async，在调用方上下文执行；UI 状态在 @MainActor 上更新 |

### B. 质量与规范

| 维度 | 结论 | 说明 |
|------|------|------|
| 架构合规 | ✅ | 搜索策略在 Domain/Service 层；繁简切换在 Presentation 层展示层面；不修改原始数据 |
| 代码风格 | ✅ | 新增方法命名清晰（exactMatch、searchMatch、processTrack、simplifyTitle）；代码结构整洁 |
| API 设计 | ✅ | autoMatchOnline 接口不变，内部实现优化；对外透明 |

### C. 性能与可维护

| 维度 | 结论 | 说明 |
|------|------|------|
| 性能 | ✅ | 降级最坏 4 次网络请求，有 7 天 cooldown 限制频率；CFStringTransform 轻量 |
| 内存管理 | ✅ | displayText 每次调用转换，不缓存（歌词行数有限，性能可接受） |
| 可维护性 | ✅ | 降级链结构清晰，新增搜索级别只需追加；simplifyTitle 正则可扩展；手动输入复用 saveLyrics |

### 逐文件检查

**LyricsService.swift**
- autoMatchOnline 重构为降级链，Level 1 用 try?（精确匹配 404 不应中断），Level 2-4 用 do-catch 统一捕获网络错误
- processTrack 提取公共逻辑，避免代码重复
- simplifyTitle 正则覆盖中文括号、英文括号、方括号以及常见后缀

**LyricsView.swift**
- @AppStorage("lyrics_simplified") 持久化繁简偏好
- displayText 方法在展示层转换，不修改原始 LyricsData
- 繁简按钮位于 header 区域收藏按钮左侧，交互位置合理
- 同步歌词和纯文本歌词均应用了转换

**LyricsSearchView.swift**
- 手动输入按钮与搜索按钮并排，使用轮廓样式区分主次
- 手动输入 sheet 使用 TextEditor + monospaced 字体，适合粘贴 LRC 格式
- 空内容时保存按钮禁用
- 保存复用 LyricsService.saveLyrics，保存后触发 onSaved + dismiss

### 问题

无 🔴/🟡 问题。
