# 方案 Review：搜索历史接入 UI - 第 1 轮

> 日期：2026-03-20 | 类型：AI 自审

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 需求覆盖 | ✅ | 展示时机、点击回填、左滑删除、清空、自动保存、Tab 独立、最多 10 条均已覆盖 |
| 可执行性 | ✅ | 基于现有 SearchService 后端，改动清晰可落地 |
| 描述清晰度 | ✅ | 逐文件改动点列出，伪代码完整，可直接编码 |
| 逻辑合理性 | ⚠️ | 见问题 1 |
| 架构合规 | ✅ | Presentation 层改动，依赖 Domain Service，方向正确 |
| 影响评估 | ✅ | 仅 2 个文件改动，不影响其他页面 |
| 边界处理 | ⚠️ | 见问题 2 |
| 性能考量 | ✅ | CoreData viewContext 查询轻量，无性能隐患 |

## 问题

1. [🟡] **clearHistory(tab:) 与 clearHistory() 行为不一致**：现有 `clearHistory()` 清空所有 Tab 历史，新增 `clearHistory(tab:)` 仅清空当前 Tab。UI 上"清空"按钮调用的是按 Tab 清空，这是合理的。但需确保函数命名不产生歧义。
   → 建议：保留两个方法，无参版本用于全局清空（目前无 UI 入口），Tab 版本用于 UI。方案文档已明确，可接受。

2. [🟡] **searchText 赋值后 onChange 触发顺序**：点击历史词时 `searchText = item.keyword; isSearchActive = true`，这会触发 `onChange(of: searchText)` → `searchDebouncer.send()`，然后 300ms 后 `onChange(of: debouncedQuery)` → `performSearch`。但 `isSearchActive` 在赋值 searchText 同帧设置为 true，而 debouncedQuery 会有 300ms 延迟，这期间可能短暂显示空状态。
   → 建议：在点击历史词时直接调用 `performSearch` 而不依赖 debounce 链，提供即时响应。同时仍设置 searchText 以保持搜索框状态。

## 修改方案

针对问题 2，修改点击历史词的逻辑：

```swift
Button {
    searchText = item.keyword
    isSearchActive = true
    isSearchFieldFocused = false
    // 立即执行搜索，不等待 debounce
    Task {
        searchResult = await searchService.search(
            query: item.keyword, tab: selectedTab, allSongs: libraryService.songs
        )
    }
} label: { ... }
```

这样用户点击历史词后立即看到搜索结果，无 300ms 延迟。
