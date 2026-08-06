# dozycat 的 agent 体系

桌面与手机不再是零散的 LLM 调用，智能行为跑在 agent 执行器上，按平台分两档：

- **桌面（首选）：真 pi**（`PiCLI.swift`）——pet spawn 本机 `pi` CLI，
  dream/searcher/chat 直接用 pi 自带的 read/bash/edit/write 工具跑在花园目录上，
  **session 落 `~/.pi/agent/sessions`（project = `~/.dozycat/garden`），
  在 pi 的 session 浏览器里可见**（dozycat·梦 / dozycat·找线索 / dozycat·聊天）。
  小传经 `moments_inbox.jsonl` 交接，pet 收件入库（store 单写者不破）。
- **回退/手机：内置循环**（`PiAgent.swift`：OpenAI 兼容 function calling）——
  没装 pi 的机器和 iOS 用它，行为定义（prompt/工具）与 pi 档完全同构。
  面向上架的自包含运行时是 pocket-pi（QuickJS），行为原样迁移。

```text
                       ┌ 每 ~5 分钟 ────────────────────────────┐
 屏幕(本机 OCR) + 前台 app │  sequence agent                      │
 + 能量/久坐 (sense) ────►│  白描 2-3 句，只写可见事实            ├─► notes/<日期>/<HHmm>_note.md
                       └──────────────────────────────────────┘
                       ┌ 每 12 次 sequence / 睡前 ──────────────┐
 notes/*.md ──────────►│  dream agent（做梦）                   ├─► people/<名>.md   人物卡
 people/*.md           │  搞清楚：人物、关系温度、用户状态        ├─► 小传 ≤3 条/天（core，跨端同步）
                       │  （承诺/情绪/身体信号）                 ├─► journal/<日期>.md 梦记
                       └──────────────────────────────────────┘
                       ┌ ⌥空格问句 ─────────────────────────────┐
 「我忘了…」 ───────────►│  searcher agent（agentic RAG）        ├─► 两句话回答 + 线索出处
                       │  工具：search_moments / grep_notes /   │
                       │  read_note / people / mdfind 文件      │
                       └──────────────────────────────────────┘
 聊天（双端）：persona + 最近小传上下文 + save_moment 工具（值得记的自己存）
```

## 数据地盘（全部本机、纯 markdown、用户可翻）

```
~/.dozycat/garden/
  notes/2026-08-06/1022_note.md   sequence 的时间笔记（frontmatter: 本地时间/app/能量）
  people/小林.md                   人物卡：关系一句话、最近温度、带日期的证据
  journal/2026-08-06.md            梦记（≤5 句）
~/.dozycat/store.db                小传 + 能量账本（Loro，跨端同步的那份）
```

分层原则（与 MOMENTS-PIPELINE 一致）：**notes 是原料**（多、碎、永不同步），
**小传是成品**（≤3 条/天，进 CRDT 跨端）；人物卡/梦记是 dream agent 的工作记忆。

## 行为调优纪律（实测出来的，别退化）

- sequence：只写屏幕可见事实，**禁止想象动作/表情/心理**；人名单独一行「人物：」；
  同分钟重跑加秒后缀防覆盖；frontmatter 用本地时间（UTC 会让 dream 误判深夜）。
- dream：先翻笔记再动手；人物卡**合并**不覆盖记忆（旧证据保留，新证据带日期）；
  save_moment 宁缺毋滥（工具侧硬性 ≤3 条/天）；笔记里没有的不写。
- searcher：中文关键词用 1-2 字短词多试；≤2 句回答 + 出处；不脑补、不编造；
  问句判定要宽（？在中间、结尾吗/呢/没、是不是/有没有/记得 都算）。
- chat：save_moment 由模型自主调用，闲聊不存，存了也不打断对话提及。

## 隐私

屏幕 OCR 在本机（Vision），截图用后即删；发给模型的只有白描/片段。
notes/people/journal 永不同步。测试用 `DOZYCAT_FAKE_OCR` 注入，真屏不出门。

## 环境变量（自动化/测试缝）

`DOZYCAT_LLM_KEY`（BYOK 注入）· `DOZYCAT_GARDEN`（花园根）· `DOZYCAT_SEQ_SECS`
（sequence 周期，默认 300）· `DOZYCAT_FAKE_OCR` · `DOZYCAT_DEBUG_OUT`（searcher
答案落文件）· debug 启动参数：`-runSequence/-runDream/-searchQuery/-searchSubmit/-chatSend`

## 路线

1. ✅ pi 循环 + 三 agent + agentic RAG（DeepSeek 实测全通）
2. pocket-pi 执行器替换（QuickJS，与 cat-poc 共享 runtime；行为定义不变）
3. 笔记/小传向量化（本地 embedding）补 grep 的召回；记事本 widget 读 notes
4. iOS 侧 dream（HealthKit + 聊天记录，无观屏）；睡前自动做梦 + 通知
