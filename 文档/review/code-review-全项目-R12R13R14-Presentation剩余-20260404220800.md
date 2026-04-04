# 代码 Review - 全项目：R12 音乐库与歌单 + R13 导入与分享 + R14 设置与订阅 - 第 1 轮

> 日期：2026-04-04 | 模式：全项目 | 类型：AI 自审

## 结论：通过

| 批次 | 🔴 | 🟡 | 🟢 |
|------|----|----|-----|
| R12 Library+Playlist | 0 | 8 | 3 |
| R13 Import+Share | 0 | 5 | 4 |
| R14 Settings+Sub | 0 | 4 | 3 |

## 主要发现（均延后）

### R12
| # | 级别 | 描述 |
|---|------|------|
| 1 | 🟡 | LibraryMainView .id(selectedTab) 导致子视图重建和重复加载 |
| 2 | 🟡 | AllSongsView onAppear 每次全量 loadSongs |
| 3 | 🟡 | PlaylistDetailView body 内 O(n log n) 排序 |
| 4 | 🟡 | SongListView recentlyPlayed pageSize:1000 全量加载 |
| 5 | 🟡 | BatchAddSongsView ForEach 以艺术家名为 id，同名冲突 |
| 6 | 🟡 | PlaylistMainView body 每帧过滤排序歌单 |

### R13
| # | 级别 | 描述 |
|---|------|------|
| 1 | 🟡 | AppleMusicImportView 大资料库 task 解码任务堆积 |
| 2 | 🟡 | AppleMusicImportViewModel 导入 Task 未暴露取消 |
| 3 | 🟡 | ShareSongSelectorView 高频输入堆积 Task.detached |

### R14
| # | 级别 | 描述 |
|---|------|------|
| 1 | 🟡 | RootTabView 三个 NavigationStack 同时常驻 |
| 2 | 🟡 | PaywallView 未在出现时 loadProducts |
