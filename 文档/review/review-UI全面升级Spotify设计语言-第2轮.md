# 方案 Review：UI 全面升级 Spotify 设计语言 - 第 2 轮

> 日期：2026-03-22 | 类型：AI 自审

## 结论：不通过（存在 3 个 🟢 优化问题需修复）

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 全部页面、Import 视图、遗漏文件均已补充 |
| 可执行性 | ✅ | PressableButtonStyle、WaveformIndicator、入场动画均有具体实现方案 |
| 描述清晰度 | ✅ | 各批次改动要点清晰，可据此直接编码 |
| 逻辑合理性 | ✅ | 色板层级（background < surface < elevatedSurface）语义清晰无重叠 |
| 架构合规 | ✅ | 复用 themedCard、ButtonStyle 替代 ViewModifier、Clean Architecture 不受影响 |
| 影响评估 | ✅ | 硬编码颜色清查完整，LyricsView 特殊场景已标注 |
| 边界处理 | ✅ | iOS 16.1 兼容策略明确，#available 保护方案清晰 |
| 性能考量 | ✅ | 多层 material 测试方案、入场动画上限、降级策略均已补充 |

## 问题

### 🟢 优化问题

**#1 文件总数描述不一致**

- 1.3 节声明「~40 个文件」
- 7 节分批计划合计为「~50 个文件」（含 6 个主题配色文件）

实际逐项统计：主题 9 + 通用 8 + 根视图 1 + 音乐库 7 + 歌单 5 + 播放器 4 + 设置 5 + Sheet 2 + Import 8 = **49 个文件**

→ **建议**：将 1.3 节的「~40」修正为「~50」。

---

**#2 ThemeVisualConfig.swift 列入文件清单但无实施细节**

2.2 节文件清单列出 `ThemeVisualConfig.swift — 视觉配置调整`，但 3.2 节各批次的详细实现中未提及对该文件的任何具体修改。

→ **建议**：在批次 1 中补充说明 ThemeVisualConfig.swift 的修改内容（如是否需要调整 `tabBarBlur` 默认值、或新增配置项），或从文件清单中移除（如无需修改）。

---

**#3 批次 1 详细实现中缺少 ImportResultView 和 QRCodeView**

分批计划表中批次 1 包含 ImportResultView 和 QRCodeView，但 3.2 节批次 1 的详细实现段落中无这两个文件的具体改动描述。

→ **建议**：补充这两个文件的改动要点（硬编码颜色清理、视觉风格对齐等）。

---

## 修改记录

### 第 1 轮问题修复确认

| # | 原问题 | 修复状态 |
|---|--------|----------|
| 1 | Import 视图遗漏 | ✅ 新增批次 7，8 个文件全部列入 |
| 2 | 其他遗漏文件 | ✅ LyricsSearchView、PlaylistGroupView、ImportResultView、QRCodeView 已补充 |
| 3 | 色板属性重叠 | ✅ 移除 3 个冗余属性，新增 4 个职责清晰的属性 |
| 4 | Modifier 与现有系统冲突 | ✅ 改为复用/扩展 themedCard |
| 5 | pressable 实现方式 | ✅ 改为 ButtonStyle |
| 6 | 动画实现细节缺失 | ✅ WaveformIndicator + VisibleRowEntranceModifier 具体方案已补充 |
| 7 | iOS 16.1 兼容性 | ✅ #available 策略已写入约束和风险评估 |
| 8 | ThemedCardModifier 硬编码 | ✅ 纳入批次 1 |
| 9 | 多层 material 性能 | ✅ 测试方案和降级策略已补充 |
| 10 | 文件计数不准确 | 🟢 部分修正（见本轮 #1） |
