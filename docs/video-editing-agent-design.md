# 视频剪辑 Agent 设计方案

## 1. 概述

### 1.1 定义

视频剪辑 Agent 是一个以 LLM 为核心推理引擎，能够理解用户自然语言意图，自主规划剪辑流程，并调用工具完成视频剪辑任务的智能系统。

### 1.2 与传统剪辑软件的区别

| 维度 | 传统剪辑软件（Premiere/剪映） | 视频剪辑 Agent |
|------|------|------|
| 交互方式 | 手动拖拽、点击 | 自然语言对话 |
| 学习成本 | 高（需学专业软件） | 低（说出需求即可） |
| 效率 | 重复操作多 | 自动批量处理 |
| 创意依赖 | 完全靠人 | AI 辅助生成创意 |

### 1.3 典型用户场景

- "把这段 30 分钟的访谈剪成 3 分钟的精华版"
- "帮我做个 Vlog，配上卡点音乐，节奏快一点"
- "把这些素材按时间顺序拼起来，转场用淡入淡出"
- "给视频加字幕，用宋体，底部居中"
- "帮我模仿这个爆款视频的风格，用我的素材重新剪一版"

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────────┐
│                    用户交互层                         │
│          (Web / App / CLI / IDE 插件)                │
└──────────────────────┬──────────────────────────────┘
                       │ 自然语言指令
                       ▼
┌─────────────────────────────────────────────────────┐
│                  Agent 核心层                        │
│  ┌───────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ LLM 推理   │  │ 规划引擎  │  │   记忆系统       │  │
│  │ (大脑)     │  │ (分解任务) │  │ (上下文/偏好)    │  │
│  └───────────┘  └──────────┘  └──────────────────┘  │
│  ┌───────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ 意图理解   │  │ 工具调度  │  │   质量检查       │  │
│  │ (NLU)     │  │ (编排执行) │  │ (结果验证)       │  │
│  └───────────┘  └──────────┘  └──────────────────┘  │
└──────────────────────┬──────────────────────────────┘
                       │ 工具调用
                       ▼
┌─────────────────────────────────────────────────────┐
│                   工具层                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │ 素材分析  │ │ 视频剪辑  │ │ 音频处理  │ │ 特效   │ │
│  │ 工具     │ │ 工具     │ │ 工具     │ │ 工具   │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │ 字幕生成  │ │ 模板引擎  │ │ 渲染导出  │ │ 素材库 │ │
│  │ 工具     │ │ 工具     │ │ 工具     │ │ 工具   │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                   基础设施层                          │
│  FFmpeg │ Whisper │ CLIP │ Stable Diffusion │ 云存储  │
└─────────────────────────────────────────────────────┘
```

---

## 3. 核心模块设计

### 3.1 意图理解模块

将用户的自然语言描述转化为结构化的剪辑指令。

```python
# 用户输入 → 结构化意图
user_input = "把这段视频剪成 1 分钟，节奏快一点，配上动感音乐"

# LLM 解析后的结构化意图
intent = {
    "action": "edit",
    "target_duration": 60,         # 秒
    "rhythm": "fast",              # fast / medium / slow
    "background_music": "dynamic", # dynamic / calm / none
    "auto_select_highlights": True # 是否自动精选片段
}
```

**关键技术**：
- Prompt Engineering：设计专用 system prompt 引导 LLM 输出结构化 JSON
- Few-shot 示例：提供典型剪辑意图的解析示例
- 多轮对话澄清：意图不明确时主动追问

### 3.2 规划引擎

将剪辑意图拆解为可执行的工具调用序列。

```
用户意图："做一个旅行 Vlog，节奏明快"
                │
                ▼
┌──────────────────────────────────────┐
│            任务规划                    │
│                                      │
│  Step 1: analyze_footage()           │
│    → 分析素材内容、时长、质量          │
│                                      │
│  Step 2: select_highlights()         │
│    → 筛选精彩片段，按精彩度排序        │
│                                      │
│  Step 3: arrange_sequence()          │
│    → 排列片段顺序，匹配目标时长        │
│                                      │
│  Step 4: add_transitions("fast_cut") │
│    → 添加快节奏转场                   │
│                                      │
│  Step 5: add_music("upbeat")         │
│    → 匹配节奏明快的背景音乐           │
│                                      │
│  Step 6: beat_sync()                 │
│    → 画面切换与音乐节拍对齐            │
│                                      │
│  Step 7: export()                    │
│    → 渲染导出                        │
└──────────────────────────────────────┘
```

**规划策略**：
- **静态模板**：预设常见剪辑流程（Vlog、访谈、产品展示等）
- **动态规划**：LLM 根据意图实时生成工具调用链
- **混合模式**：模板 + 动态，先匹配模板再微调

### 3.3 工具层

Agent 的"手"，每个工具封装一个具体的剪辑能力。

#### 3.3.1 素材分析工具

```python
class FootageAnalyzer:
    """分析视频素材的内容和质量"""

    def analyze(self, video_path: str) -> dict:
        return {
            "duration": 120,           # 时长
            "resolution": "1920x1080", # 分辨率
            "scenes": [                # 场景分割
                {"start": 0, "end": 15, "type": "outdoor", "tags": ["mountain", "sunset"]},
                {"start": 15, "end": 30, "type": "indoor", "tags": ["food", "restaurant"]},
            ],
            "faces": [                 # 人脸检测
                {"timestamp": 5, "duration": 10, "person": "unknown"},
            ],
            "audio_quality": "good",   # 音频质量
            "stability": "stable",     # 画面稳定性
            "highlights": [            # 精彩度评分
                {"start": 0, "end": 8, "score": 0.92},
                {"start": 45, "end": 60, "score": 0.85},
            ]
        }
```

**依赖技术**：
- 场景检测：PySceneDetect
- 内容识别：CLIP / BLIP（图像描述生成）
- 人脸检测：MediaPipe / InsightFace
- 精彩度评估：基于画面变化频率、音频能量、人脸表情的综合评分模型

#### 3.3.2 视频剪辑工具

```python
class VideoEditor:
    """执行具体的视频剪辑操作"""

    def cut(self, video_path: str, start: float, end: float) -> str:
        """剪切片段"""
        # 调用 FFmpeg
        pass

    def concat(self, clips: list[str], transitions: str = "none") -> str:
        """拼接片段，添加转场"""
        pass

    def add_subtitles(self, video_path: str, subtitles: list[dict]) -> str:
        """添加字幕"""
        pass

    def adjust_speed(self, video_path: str, speed: float) -> str:
        """调整播放速度"""
        pass

    def add_transition(self, clip_a: str, clip_b: str, type: str) -> str:
        """添加转场效果 (fade/dissolve/wipe/zoom)"""
        pass
```

#### 3.3.3 音频处理工具

```python
class AudioProcessor:
    """处理视频音频"""

    def extract_beats(self, audio_path: str) -> list[float]:
        """提取节拍时间点"""
        pass

    def analyze_mood(self, audio_path: str) -> str:
        """分析音乐情绪 (happy/sad/energetic/calm)"""
        pass

    def mix_audio(self, video_path: str, music_path: str,
                  volume_ratio: float = 0.3) -> str:
        """混音：视频原声 + 背景音乐"""
        pass

    def auto_duck(self, video_path: str) -> str:
        """说话时自动降低背景音乐音量"""
        pass
```

#### 3.3.4 字幕生成工具

```python
class SubtitleGenerator:
    """语音识别 + 字幕生成"""

    def transcribe(self, video_path: str, language: str = "zh") -> list[dict]:
        """语音转文字，返回带时间戳的字幕"""
        # 依赖 Whisper
        return [
            {"text": "今天来到了美丽的西湖", "start": 0.0, "end": 2.5},
            {"text": "这里的风景真的很美", "start": 2.5, "end": 4.8},
        ]

    def style_subtitle(self, subtitles: list[dict],
                       font: str = "宋体", position: str = "bottom") -> str:
        """设置字幕样式"""
        pass
```

#### 3.3.5 模板引擎

```python
class TemplateEngine:
    """预设剪辑模板，快速套用"""

    templates = {
        "vlog_fast": {
            "name": "快节奏Vlog",
            "target_clip_duration": 3,     # 每个片段 3 秒
            "transitions": ["zoom_in", "swipe_left"],
            "music_mood": "upbeat",
            "subtitle_style": "dynamic",
        },
        "product_showcase": {
            "name": "产品展示",
            "target_clip_duration": 5,
            "transitions": ["fade", "dissolve"],
            "music_mood": "professional",
            "subtitle_style": "clean",
        },
        "interview_highlight": {
            "name": "访谈精华",
            "target_clip_duration": 10,
            "transitions": ["cross_dissolve"],
            "music_mood": "ambient",
            "subtitle_style": "full_transcript",
        }
    }

    def apply(self, template_name: str, footage: dict) -> list[dict]:
        """将模板应用到素材"""
        pass
```

### 3.4 记忆系统

```python
class MemorySystem:
    """Agent 的记忆管理"""

    def save_preference(self, user_id: str, preference: dict):
        """保存用户偏好"""
        # 例：用户喜欢快节奏、偏好动感音乐、常用宋体字幕
        pass

    def save_project(self, project_id: str, state: dict):
        """保存项目状态，支持中断续编"""
        pass

    def save_style(self, name: str, config: dict):
        """保存自定义风格（从历史项目中提取）"""
        pass

    def recall(self, context: dict) -> dict:
        """根据当前上下文检索相关记忆"""
        pass
```

**记忆内容**：

| 记忆类型 | 内容示例 | 用途 |
|---------|---------|------|
| 用户偏好 | 喜欢快节奏、偏好无字幕 | 自动应用偏好设置 |
| 项目历史 | 上次剪辑用了什么模板 | 推荐相似风格 |
| 审美风格 | 偏好暖色调、电影感 | 调色/滤镜推荐 |
| 反馈纠正 | "转场太快了" | 下次自动调整 |
| 常用素材 | 常用 BGM、片头片尾 | 快速复用 |

### 3.5 质量检查模块

每一步工具调用后自动检查输出质量：

```python
class QualityChecker:
    """质量把关"""

    def check_duration(self, result: str, target: float) -> bool:
        """检查时长是否符合目标"""

    def check_smoothness(self, video_path: str) -> float:
        """检查转场是否流畅 (0~1 评分)"""

    def check_audio_sync(self, video_path: str) -> float:
        """检查音画同步 (0~1 评分)"""

    def check_subtitle_accuracy(self, subtitles: list, audio: str) -> float:
        """检查字幕与语音是否匹配"""

    def overall_score(self, video_path: str) -> dict:
        """综合质量评分"""
        return {
            "visual_quality": 0.85,
            "audio_quality": 0.90,
            "rhythm_score": 0.78,
            "subtitle_accuracy": 0.95,
            "overall": 0.87
        }
```

---

## 4. 核心工作流

### 4.1 基础流程

```
用户输入 ──→ 意图理解 ──→ 任务规划 ──→ 工具执行 ──→ 质量检查 ──→ 输出结果
   │                                          │            │
   │              ┌───────────────────────────┘            │
   │              ▼ 不合格                                  ▼ 合格
   │          重新规划/调整参数                         展示给用户
   │                                                          │
   └──────────────────── 用户反馈 ←───────────────────────────┘
                        │
                        ▼
                    保存记忆（偏好/纠正）
```

### 4.2 详细交互示例

```
👤 用户：把这几段旅行素材剪一个 60 秒的 Vlog，风格轻松愉快

🤖 Agent：
  📋 理解意图：旅行 Vlog / 60 秒 / 轻松愉快风格
  📊 分析素材：共 5 段，总计 15 分钟
  🎯 开始剪辑计划：

  Step 1/6 → 分析素材内容... ✅
    检测到场景：海滩、街道、美食、日落

  Step 2/6 → 筛选精彩片段... ✅
    选出 20 个候选片段（总计 180 秒）

  Step 3/6 → 排列片段顺序... ✅
    按叙事逻辑排序，裁剪至 60 秒

  Step 4/6 → 添加转场和音乐... ✅
    使用轻快转场 + Ukulele 背景乐

  Step 5/6 → 节拍对齐... ✅
    画面切换点与音乐节拍对齐

  Step 6/6 → 渲染导出... ✅
    输出：travel_vlog_60s.mp4

  📊 质量评分：87/100
  💡 建议：日落片段可以稍长一些，效果更好

👤 用户：日落那段再长一点，字幕加上

🤖 Agent：
  📋 调整：延长日落片段 / 添加字幕
  🔄 执行调整... ✅
  📝 字幕已生成（Whisper 语音识别）
  📊 重新导出完成
```

### 4.3 关键决策流程

Agent 在执行过程中需要做出多个创意决策：

```
                    剪辑决策树
                        │
            ┌───────────┴───────────┐
            │                       │
        目标时长分配              风格确定
            │                       │
    ┌───────┼───────┐       ┌───────┼───────┐
    │       │       │       │       │       │
  总时长  片段数  单段时长  转场    音乐    节奏
    │       │       │       │       │       │
  60s     20段    ~3s     快切    轻快    明快
```

这些决策由 LLM 根据以下因素综合判断：
- 用户明确指令
- 素材内容特征
- 历史偏好记忆
- 剪辑行业经验（通过 system prompt 注入）

---

## 5. 技术选型

### 5.1 推荐技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| LLM | Claude / GPT-4o | 意图理解、任务规划、创意决策 |
| 视频处理 | FFmpeg | 剪切、拼接、转码、渲染 |
| 语音识别 | Whisper | 字幕生成 |
| 图像理解 | CLIP / GPT-4V | 素材内容分析 |
| 音频分析 | librosa | 节拍检测、情绪分析 |
| 后端 | Python (FastAPI) | Agent 服务 |
| 任务队列 | Celery + Redis | 异步处理耗时任务 |
| 存储 | S3 / MinIO | 素材和成品存储 |
| 数据库 | PostgreSQL | 项目、记忆、模板存储 |

### 5.2 Agent 框架选择

| 框架 | 特点 | 适合场景 |
|------|------|---------|
| LangChain | 生态丰富、工具多 | 快速原型 |
| LangGraph | 支持状态图、复杂流程 | 需要精细控制流程 |
| CrewAI | 多 Agent 协作 | 复杂任务分工 |
| 自研 | 完全可控 | 定制化需求强 |

**推荐**：初期用 LangGraph，它支持复杂的有状态工作流，适合视频剪辑这种多步骤、有依赖关系的场景。

### 5.3 部署方案

```
轻量方案（MVP）：
  LLM API (Claude/GPT) + FFmpeg 服务器
  预算：~$200-500/月

标准方案（生产级）：
  LLM API + FFmpeg 集群 + 对象存储 + 任务队列
  预算：~$2000-5000/月

高性能方案（大规模）：
  LLM API + GPU 渲染集群 + CDN + 微服务架构
  预算：$10000+/月
```

---

## 6. 核心难点与解决方案

### 6.1 LLM 不直接处理视频

**问题**：LLM 只能处理文本，无法"看"视频。

**解决方案**：
```
方案一：多模态 LLM（GPT-4V / Claude Vision）
  → 抽关键帧 → 发给 LLM 看 → 理解内容
  → 优点：简单直接
  → 缺点：成本高、速度慢

方案二：专用视觉模型 + LLM 协作
  → CLIP 做场景分类 → BLIP 生成描述 → LLM 做决策
  → 优点：分工明确、效率高
  → 缺点：需要多个模型

方案三（推荐）：分层架构
  → 底层：传统 CV 模型做结构化分析（场景、人脸、运动）
  → 中层：将分析结果转为文本描述
  → 上层：LLM 基于文本描述做决策
```

### 6.2 剪辑创意的主观性

**问题**："好看"没有客观标准，Agent 的审美可能不符合用户。

**解决方案**：
- **偏好学习**：记忆用户的反馈（"转场太快"、"音乐太吵"），逐步校准
- **多版本输出**：生成 2-3 个不同风格版本供用户选择
- **交互式微调**：支持"这段换一个"、"这里加慢动作"等精细调整
- **评分反馈**：用户对结果评分，作为未来决策的参考

### 6.3 实时性与计算成本

**问题**：视频渲染耗时，用户等待体验差。

**解决方案**：
- **预览模式**：先生成低分辨率预览，确认后再渲染高清
- **异步处理**：耗时操作入队列，通知用户结果
- **流式反馈**：每完成一步实时展示进度
- **缓存复用**：相似素材复用分析结果

### 6.4 复杂剪辑任务的可靠性

**问题**：Agent 可能生成错误的工具调用序列。

**解决方案**：
- **沙箱执行**：在安全环境中试运行，不影响原始素材
- **回滚机制**：每步操作可撤销，支持回到上一个状态
- **人工确认点**：关键决策前暂停请用户确认
- **质量门控**：每步自动检查，不合格自动重试或回退

---

## 7. MVP（最小可行产品）范围建议

### Phase 1 — 基础版（4-6 周）

- [x] 自然语言意图解析
- [x] 基于模板的自动剪辑（3-5 个预设模板）
- [x] 基础素材分析（时长、场景数）
- [x] FFmpeg 剪切 + 拼接 + 转场
- [x] Whisper 字幕生成
- [x] 简单的背景音乐匹配
- [x] Web 端对话交互

### Phase 2 — 进阶版（+4-6 周）

- [ ] 精彩片段智能筛选
- [ ] 音乐节拍对齐
- [ ] 用户偏好记忆
- [ ] 多版本输出
- [ ] 交互式微调
- [ ] 质量评分系统

### Phase 3 — 高级版（+4-6 周）

- [ ] 自定义模板创建
- [ ] 风格迁移（模仿参考视频的风格）
- [ ] 多 Agent 协作（剪辑 Agent + 配乐 Agent + 字幕 Agent）
- [ ] 批量处理
- [ ] API 开放平台

---

## 8. 总结

视频剪辑 Agent 的核心设计思路：

1. **LLM 是大脑** — 负责理解、规划、决策，不直接处理视频
2. **工具是双手** — FFmpeg、Whisper、CLIP 等工具执行具体操作
3. **记忆是经验** — 记住用户偏好，越用越懂你
4. **质量检查是底线** — 每步验证，确保输出可用
5. **人是最终裁判** — Agent 提供建议和执行，人做最终决策

关键成功因素：不追求一步到位的"全自动"，而是做好 **"AI 建议 → 人确认 → AI 执行 → 人反馈"** 的循环。
