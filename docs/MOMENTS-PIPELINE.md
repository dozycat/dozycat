# 桌面端「观屏 → 小传」管线

桌面端的核心功能：看屏幕/鼠标/键盘，替你把一天过成「小传」。
接在 FATIGUE.md 的感知层之上，是它的**内容侧姊妹管线**（疲劳管线是内容盲的，
本管线看内容——所以边界、预算、隐私都要单独说清楚）。

## 分层（延续 pb-os 的铁律：原始数据不出守护进程）

```text
采集（5min 窗口）
  ├─ 截屏若干张（ScreenCaptureKit，变化驱动 + 上限）
  ├─ 输入节奏/前台 app（复用 dozycat-sense）
  └─ 隐私门（secure input / 黑名单 app / 手动暂停）→ 触发即整窗丢弃
      ↓
Sequence（5min → 1 条，本地）
  拼图：该窗口的截屏缩略拼成一张 collage + 元信息（app 序列、时长）
  → BYOK LLM（多模态）："这 5 分钟用户在经历什么"→ 一段事实描述
  → 写入【记事本】（notebook，本地明细账，桌面 widget 可翻看）
      ↓
小传蒸馏（每日 ≤3 条，节流在这里！）
  睡前/定时：把当天的 sequence 描述串给 LLM 二次蒸馏——
  "挑出今天真正值得被记住的 ≤3 件小事，用懒猫的口吻写"
  → 写入 dozycat-core（跨端同步，手机「小传」页看到的就是这个）
```

**密度控制的关键设计**：sequence 是原料（一天 ~100 条，只进本地记事本，
永不同步、永不直接示人），小传是成品（**一天 ≤3 条**，经蒸馏才进 core）。
两层分开，既有完整明细可查，又不会把「小传」灌成流水账。

## 记事本 widget（桌面端）

- 桌宠旁的一个轻量窗口（点猫展开）：按时间倒序的 sequence 明细，
  可搜索、可删除（删除 = 本地物理删，因为根本没进 CRDT）
- 某条 sequence 值得记？一键"收进小传"（手动补充蒸馏的遗漏）
- 隐私开关就近：暂停观察 N 小时 / 应用黑名单

## BYOK 与预算

- LLM 全部走用户自己的 Key（设置里配，与 iOS 同一套 provider 抽象：
  OpenAI / DeepSeek / 自定义 OpenAI 兼容端点；桌面读同一配置概念）
- 成本量级（多模态 mini 级模型）：5min 一次 collage 描述 + 每日一次蒸馏，
  重度使用 ~1-2 美元/月量级；sequence 描述可以用便宜模型，蒸馏用好模型
- 无 Key 时：管线不跑，桌宠只保留疲劳感知（内容盲）——产品可用性分级清晰

## 隐私（比疲劳管线更严）

- 截屏只在内存中拼图，发给 LLM 后即弃；本地只留文字描述（记事本），
  不留图（v1 可选留缩略，默认不留）
- secure input / 密码管理器 / 隐私黑名单 / 私密浏览 → 整个 5min 窗口作废
- 记事本永不同步；小传经蒸馏才进 core（同步的是密文，见 MEMORY-SYNC.md）
- 明确的暂停开关 + 菜单栏状态可见（在看/没在看，如 cat-poc 的猫转头）

## 里程碑

1. `dozycat-scribe` crate：ScreenCaptureKit 截屏（Rust objc2 或 Swift helper）+
   变化检测 + collage 拼图（复用 cat-poc `cat-sense` 的 MSE 去重思路）
2. sequence 描述：OpenAI 兼容多模态调用（Rust 侧 reqwest，或经 pet 的 Swift 层）
3. 记事本 widget（pet-mac 内 SwiftUI 窗口 + 本地 SQLite）
4. 每日蒸馏 → core 写入 ≤3 条小传（带「来自桌面」标记）
5. 隐私门与 sense 打通（secure-input 信号共享）、暂停 UI
